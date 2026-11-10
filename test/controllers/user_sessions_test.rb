require "test_helper"

# One person at one screen: a user holds as many sessions as their limit (one unless the
# administrator says otherwise), a screen nobody uses closes by itself, and none of it touches
# the shift or loses a sale.
class UserSessionsTest < ActionDispatch::IntegrationTest
  CHROME = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36".freeze
  JSON_HEADERS = { "Accept" => "application/json" }.freeze

  setup { SessionsController::ATTEMPTS.clear }

  # A separate browser, signed in.
  def device(user, agent: CHROME)
    open_session.tap { |d| d.post login_path, params: { user: user, password: "secret12" }, headers: { "User-Agent" => agent } }
  end

  def signed_in?(d)
    d.get inventory_path
    d.response.successful?
  end

  def assert_sent_to_sign_in(d, message)
    d.get inventory_path
    d.assert_redirected_to login_path
    assert_match message, d.flash[:alert]
  end

  test "with a limit of one, signing in elsewhere ends the first session and that device is told why" do
    a = device("cashier")
    assert signed_in?(a)
    b = device("cashier")
    assert signed_in?(b)
    a.get till_token_path, headers: JSON_HEADERS
    assert_equal 401, a.response.status
    assert_equal true, a.response.parsed_body["signed_out"]
    assert_match "opened on another device", a.response.parsed_body["error"]
    a.get inventory_path
    a.assert_redirected_to login_path
    assert_match "Sign in to continue", a.flash[:alert], "it is told once; after that it is just a device without a session"
    assert signed_in?(b)
    assert_equal 1, users(:cashier).sessions.count
  end

  test "the device left behind is told why on a page too" do
    a = device("cashier")
    device("cashier")
    assert_sent_to_sign_in a, "opened on another device"
  end

  test "with a limit of two the oldest of three goes; two different users never get in each other's way" do
    users(:cashier).update!(session_limit: 2)
    a = device("cashier")
    travel 1.second
    b = device("cashier")
    travel 1.second
    other = device("supervisor")
    c = device("cashier")
    assert_not signed_in?(a)
    assert signed_in?(b)
    assert signed_in?(c)
    assert signed_in?(other)
    assert_equal [ 2, 1 ], [ users(:cashier).sessions.count, users(:supervisor).sessions.count ]
  end

  test "the limit is set in the user form by whoever manages users, between 1 and 5; lowering it ends the surplus" do
    admin = device("admin")
    admin.get edit_admin_user_path(users(:cashier))
    admin.assert_select "input[name='user[session_limit]'][min='1'][max='5'][value='1']"
    admin.patch admin_user_path(users(:cashier)), params: { user: { name: "Cashier", user: "cashier", session_limit: "2" } }
    assert_equal 2, users(:cashier).reload.session_limit
    a = device("cashier")
    travel 1.second
    b = device("cashier")
    assert signed_in?(a) && signed_in?(b)
    [ "0", "6", "many" ].each do |limit|
      admin.patch admin_user_path(users(:cashier)), params: { user: { name: "Cashier", user: "cashier", session_limit: limit } }
      assert_equal 422, admin.response.status, limit
    end
    assert_equal 2, users(:cashier).reload.session_limit
    admin.patch admin_user_path(users(:cashier)), params: { user: { name: "Cashier", user: "cashier", session_limit: "1" } }
    assert_not signed_in?(a)
    assert signed_in?(b)
    b.patch admin_user_path(users(:cashier)), params: { user: { name: "Cashier", user: "cashier", session_limit: "5" } }
    assert_equal 403, b.response.status
    assert_equal 1, users(:cashier).reload.session_limit
  end

  test "a screen nobody uses closes: fine at 14 minutes, gone well after the countdown, and told why" do
    a = device("cashier")
    travel 14.minutes
    assert signed_in?(a), "inside the 15 minutes"
    travel 14.minutes
    assert signed_in?(a), "and using it started the 15 minutes over"
    travel UserSession::IDLE_AFTER + UserSession::COUNTDOWN + UserSession::GRACE + 1.second
    assert_sent_to_sign_in a, "closed after 15 minutes without use"
    assert_equal 0, users(:cashier).sessions.count

    b = device("cashier")
    travel 20.minutes
    b.get till_token_path, headers: JSON_HEADERS
    assert_equal [ 401, true ], [ b.response.status, b.response.parsed_body["signed_out"] ]
    assert_match "without use", b.response.parsed_body["error"]
  end

  test "answering 'I'm still here' keeps the session; what the page does by itself does not" do
    a = device("cashier")
    4.times do
      travel 12.minutes
      a.post keep_session_path
      assert_equal 204, a.response.status
    end
    assert signed_in?(a), "48 minutes in, kept alive by answering"

    till = device("supervisor")
    6.times do
      travel 4.minutes
      till.get till_token_path, headers: JSON_HEADERS.merge("X-Background" => "1")
    end
    assert_equal 401, till.response.status, "a till left alone ends even though it kept looking for sales to upload"
    assert_not signed_in?(till)
    a.post keep_session_path, headers: JSON_HEADERS
    assert_equal 401, a.response.status, "and nothing is left to keep on a session that ran out"
  end

  test "signing out ends that session for real and leaves the user's other ones alone" do
    users(:cashier).update!(session_limit: 2)
    a = device("cashier")
    b = device("cashier")
    copied = a.cookies["user_id"]
    a.delete logout_path
    a.assert_redirected_to login_path
    a.cookies["user_id"] = copied
    assert_not signed_in?(a), "the cookie it had is worth nothing now"
    assert signed_in?(b)
    b.delete logout_path, params: { idle: "1" }
    assert_match "closed after 15 minutes without use", b.flash[:notice], "the countdown nobody answered says so"
    assert_equal 0, UserSession.count
  end

  test "a new password or a switched-off user ends every session; changing one's own keeps the one in use" do
    users(:admin).update!(session_limit: 2)
    desktop = device("admin")
    phone = device("admin")
    cashier = device("cashier")
    desktop.patch admin_user_path(users(:cashier)), params: { user: { name: "Cashier", user: "cashier", password: "another12" } }
    assert_not signed_in?(cashier)
    desktop.patch admin_user_path(users(:admin)), params: { user: { name: "Administrator", user: "admin", password: "another12" } }
    desktop.assert_redirected_to admin_users_path
    assert signed_in?(desktop), "the device where it was changed stays in"
    assert_not signed_in?(phone)
    supervisor = device("supervisor")
    users(:supervisor).update!(active: false)
    assert_not signed_in?(supervisor)
  end

  test "the user list shows who is signed in and on what, and ends a session; only with the permission" do
    cashier = device("cashier")
    admin = device("admin", agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1")
    admin.get admin_users_path
    admin.assert_select "td", /Chrome · Windows · since/
    admin.assert_select "td", /Safari · iPhone · since/
    session = users(:cashier).sessions.sole
    cashier.delete admin_user_session_path(users(:admin), users(:admin).sessions.sole)
    assert_equal 403, cashier.response.status
    assert signed_in?(admin)
    admin.delete admin_user_session_path(users(:cashier), session)
    admin.assert_redirected_to admin_users_path
    assert_match "Cashier's session was ended", admin.flash[:notice]
    assert_sent_to_sign_in cashier, "an administrator ended it"
    admin.delete admin_user_session_path(users(:admin), session.id)
    assert_equal 404, admin.response.status, "a session is ended under its own user, and only once"
  end

  test "however a session ends, the shift stays open with its figures and whoever signs in next sells on it" do
    shift = shifts(:store_open)
    Inventory.move!(branch: branches(:store), product: products(:ketchup), kind: "inflow", quantity: 9, user: users(:admin))
    sell = ->(d, key) { d.post till_checkout_path, params: { key: key, lines: [ { product_id: products(:ketchup).id, quantity: 1 } ].to_json, payments: [ { payment_method: "cash", amount_cents: 4_200 } ].to_json }, headers: JSON_HEADERS }
    a = device("cashier")
    sell.(a, "s1")
    device("cashier")                                                  # opened elsewhere
    b = device("cashier")
    travel 30.minutes                                                  # left unused
    assert_not signed_in?(b)
    c = device("cashier")
    c.delete logout_path                                               # signed out
    assert_equal [ "open", 54_200, 1 ], [ shift.reload.status, shift.expected_cash_cents, shift.sales.count ]
    sell.(device("supervisor"), "s2")
    assert_equal [ "open", 58_400, 2 ], [ shift.reload.status, shift.expected_cash_cents, shift.sales.count ]

    users(:cashier).update!(branch: branches(:head_office))            # the same user, now at another branch
    moved = device("cashier")
    moved.get till_path
    moved.assert_select "form[action='#{till_open_path}']", 1, "that branch has its own shift to open, with its own float"
    assert shift.reload.open?, "and the one left behind waits to be counted"
  end

  test "the screens carry what the browser needs: the idle dialog when signed in, the seller at the till" do
    get login_path
    assert_select "[data-idle-target]", 0
    a = device("cashier")
    a.get till_path
    a.assert_select "body[data-controller~=idle][data-idle-after-value='900'][data-idle-countdown-value='60'][data-idle-keep-url-value='#{keep_session_path}']"
    a.assert_select "dialog[data-idle-target=dialog]" do
      a.assert_select "*", /Are you still there\?/
      a.assert_select "[data-idle-target=clock]"
      a.assert_select "button[data-action='idle#stay']", "I'm still here"
    end
    a.assert_select "[data-controller=pos][data-pos-user-value='#{users(:cashier).id}'][data-pos-login-url-value='#{login_path}']"
  end

  test "a cookie that was never a session just asks to sign in" do
    get inventory_path
    assert_redirected_to login_path
    assert_match "Sign in to continue", flash[:alert]
    cookies["user_id"] = "made-up"
    get till_token_path, headers: JSON_HEADERS
    assert_equal [ 401, true ], [ response.status, response.parsed_body["signed_out"] ]
    assert_match "Sign in to continue", response.parsed_body["error"]
  end
end
