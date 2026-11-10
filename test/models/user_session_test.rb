require "test_helper"

class UserSessionTest < ActiveSupport::TestCase
  test "starting a session stores only the digest of its token and finds it back by the token" do
    session, token = UserSession.start!(users(:cashier), user_agent: "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0")
    assert_operator token.length, :>=, 40
    assert_not_equal token, session.token_digest
    assert_not_includes session.attributes.values.map(&:to_s), token
    assert_equal "Firefox · Linux", session.device
    assert_equal session, UserSession.find_live(session.id, token)
    assert_nil UserSession.find_live(session.id, token.reverse)
    assert_nil UserSession.find_live(session.id, "")
    assert_nil UserSession.find_live("#{session.id} OR 1=1", token)
    assert_nil UserSession.find_live(nil, nil)
  end

  test "beyond the user's limit the oldest sessions end; other users' are never touched" do
    cashier = users(:cashier)
    other, = UserSession.start!(users(:supervisor))
    first, = UserSession.start!(cashier)
    travel 1.second
    second, = UserSession.start!(cashier)
    assert_equal [ second ], cashier.sessions.to_a
    assert_not UserSession.exists?(first.id)
    cashier.update!(session_limit: 3)
    travel 1.second
    third, = UserSession.start!(cashier)
    travel 1.second
    fourth, = UserSession.start!(cashier)
    travel 1.second
    fifth, = UserSession.start!(cashier)
    assert_equal [ third, fourth, fifth ], cashier.sessions.order(:started_at).to_a
    cashier.update!(session_limit: 1)
    assert_equal [ fifth ], cashier.sessions.reload.to_a
    assert UserSession.exists?(other.id)
  end

  test "the limit is a whole number from 1 to 5" do
    [ 0, 6, -1, 1.5, nil ].each { |limit| assert_not users(:cashier).update(session_limit: limit), limit.inspect }
    (1..5).each { |limit| assert users(:cashier).update(session_limit: limit) }
    assert_equal 1, User.new.session_limit, "one out of the box"
  end

  test "a session goes idle after the 15 minutes, the countdown and the margin; using it starts over" do
    session, = UserSession.start!(users(:cashier))
    travel UserSession::IDLE_AFTER + UserSession::COUNTDOWN
    assert_not session.idle?, "the screen's own clock may run a little ahead of the server's"
    travel UserSession::GRACE + 1.second
    assert session.idle?
    session.use!
    assert_not session.reload.idle?
    used = session.last_used_at
    travel 5.seconds
    session.use!
    assert_equal used, session.reload.last_used_at, "it is not written on every single request"
    travel 10.seconds
    session.use!
    assert_operator session.reload.last_used_at, :>, used
  end

  test "the device is read from the browser's name for itself, and an unknown one is left blank" do
    {
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36" => "Chrome · Windows",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0" => "Edge · Windows",
      "Mozilla/5.0 (Linux; Android 16; moto g55) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36" => "Chrome · Android",
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1" => "Safari · iPhone",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15" => "Safari · Mac",
      "Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36" => "Chrome · ChromeOS",
      "curl/8.5.0" => nil, "" => nil, nil => nil
    }.each { |agent, device| assert_nil_or_equal device, UserSession.device(agent), agent.inspect }
  end

  def assert_nil_or_equal(expected, actual, message)
    expected.nil? ? assert_nil(actual, message) : assert_equal(expected, actual, message)
  end

  test "a new password or switching the user off ends their sessions; other changes do not" do
    cashier = users(:cashier)
    UserSession.start!(cashier)
    cashier.update!(name: "Renamed", language: "es")
    assert_equal 1, cashier.sessions.count
    cashier.update!(password: "another12")
    assert_equal 0, cashier.sessions.count
    UserSession.start!(cashier)
    cashier.update!(active: false)
    assert_equal 0, cashier.sessions.count
  end
end
