require "test_helper"

class ReturnablesScreensTest < ActionDispatch::IntegrationTest
  JSON_HEADERS = { "Accept" => "application/json" }.freeze

  setup do
    Features.store!(Features::OPTIONAL, check: false)
    @store = branches(:store)
    @store.update!(cash_limit_cents: 100_000_000)
    users(:admin).update!(branch: @store)
    @chicken = products(:chicken)
    @ketchup = products(:ketchup)
    Inventory.move!(branch: @store, product: @chicken, kind: "inflow", quantity: 500, user: users(:admin))
    Inventory.move!(branch: @store, product: @ketchup, kind: "inflow", quantity: 500, user: users(:admin))
    @lupita = Customer.create!(name: "Lupita's Diner")
    sign_in "admin"
  end

  def sign_in(user)
    delete logout_path
    post login_path, params: { user: user, password: "secret12" }
  end

  def declare(code = ReturnableRule::EXAMPLE) = Rule.create!(hook: "returnable", code: code, user: users(:admin))
  def owe(pieces, kind: "crate") = Returnables.move!(@lupita, kind, pieces, "out", user: users(:admin), branch: @store)
  def account = @lupita.returnable_account

  def checkout(returnables: nil, lines: [ { product_id: @ketchup.id, quantity: 1 } ], customer: @lupita, **extra)
    post till_checkout_path, headers: JSON_HEADERS, params: { key: SecureRandom.uuid, lines: lines.to_json, customer_id: customer&.id,
      payments: [ { payment_method: "cash", amount_cents: 10_000_000 } ].to_json, returnables: returnables&.to_json, **extra }.compact
  end

  test "with the feature off nothing about returnables shows anywhere, and its screens are not there" do
    declare
    owe(3)
    Features.store!(Features::OPTIONAL - %w[returnables], check: false)
    get till_path
    assert_select "#returnables", 0
    assert_select "#more_than_owed", 0
    get account_customer_path(@lupita)
    assert_select "#returnables", 0
    get customers_path
    assert_select "td[data-returnables]", 0
    get edit_admin_product_path(@chicken)
    assert_select "#product_returnables", 0
    get settings_section_path("for_you")
    assert_select "a[href=?]", rule_edit_path("returnable"), 0
    get rule_edit_path("returnable")
    assert_response :not_found
    post customer_returnables_receive_path(@lupita), params: { kind: "crate", quantity: 1 }
    assert_response :not_found
    assert_equal 3, account.owed("crate")
    patch admin_product_path(@chicken), params: { product: { returnable: "1" } }
    assert_not @chicken.reload.returnable?, "the product form does not take it either"
  end

  test "the feature needs customers, and switched on with nothing declared the till asks for nothing" do
    assert_equal %w[customers], Features.needs("returnables")
    Features.store!(%w[purchases], check: false)
    Features.store!(%w[purchases returnables], check: false)
    assert Features.active?("customers"), "switching it on brings customers along"
    assert_match "Returnables", assert_raises(ArgumentError) { Features.store!(%w[purchases returnables], check: false) }.message, "and customers cannot go while it is on"

    Features.store!(Features::OPTIONAL, check: false)
    get till_path
    assert_select "select[name=customer_id]"
    assert_select "#returnables", 0
    get settings_section_path("for_you")
    assert_select "a[href=?]", rule_edit_path("returnable")
    get new_admin_role_path
    assert_select "input[value='returnables.in_favor']"
  end

  test "at the till: counters per declared kind, what a product releases travels with the scan, and the ticket prints the pieces" do
    declare
    @chicken.returnables.build(kind: "crate", from_quantity: 15)
    @chicken.update!(returnable: true)
    get till_path
    assert_select "#returnables[hidden] tr[data-kind]", 2
    assert_select "#returnables tr[data-kind=crate][data-name=Crate] input[data-role=out]"
    assert_select "#returnables tr[data-kind=bottle] input[data-role=back]"
    assert_select "dialog#more_than_owed button[data-action='pos#acceptInFavor'][hidden]"
    get till_scan_path(code: "CHKN"), headers: JSON_HEADERS
    assert_equal [ { "kind" => "crate", "from" => 15.0, "per" => nil } ], response.parsed_body["returnables"]
    get till_scan_path(code: "KETC"), headers: JSON_HEADERS
    assert_equal [], response.parsed_body["returnables"]
    get till_catalog_path, headers: JSON_HEADERS
    assert_equal [ "crate" ], response.parsed_body["products"].find { |p| p["key"] == "CHKN" }["returnables"].map { |r| r["kind"] }

    owe(4)
    checkout(returnables: [ { kind: "crate", out: 5, back: 2 }, { kind: "bottle", out: 0, back: 0 } ])
    assert_response :ok
    assert_equal 7, account.owed("crate")
    get till_ticket_path(Sale.last)
    assert_select "table[data-ticket=returnables] tr", 1
    assert_select "table[data-ticket=returnables] td", "Crate"
    assert_select "table[data-ticket=returnables] td", "5 out, 2 back"
    assert_select "table[data-ticket=returnables] td", "owes 7"
    checkout(customer: nil)
    get till_ticket_path(Sale.last)
    assert_select "table[data-ticket=returnables]", 0

    checkout(returnables: [ { kind: "crate", out: 1 } ], customer: nil)
    assert_response :unprocessable_entity
    assert_match "choose the customer", response.parsed_body["error"]
    checkout(returnables: "not a list")
    assert_response :ok, "anything that is not a list of pieces counts as nothing typed"
  end

  test "the till stops a sale that breaks the rule, and more coming back than owed gets its own answer" do
    declare
    owe(10)
    sign_in "cashier"
    checkout(returnables: [ { kind: "crate", out: 1 } ])
    assert_response :unprocessable_entity
    assert_match "Crate: Lupita's Diner already holds too many (10 × Crate)", response.parsed_body["error"]
    assert_match "It has been reported", response.parsed_body["error"]
    assert Review.last.stopped?

    checkout(returnables: [ { kind: "crate", back: 11 } ])
    assert_response :unprocessable_entity
    body = response.parsed_body
    assert_equal [ { "kind" => "crate", "name" => "Crate", "owed" => 10, "back" => 11 } ], body["more_than_owed"]
    assert_equal false, body["can_accept"]
    checkout(returnables: [ { kind: "crate", back: 11 } ], accept_in_favor: "1")
    assert_response :unprocessable_entity, "saying so is not enough without the permission"
    assert_equal [ 10, 1 ], [ account.owed("crate"), Review.count ]

    sign_in "admin"
    checkout(returnables: [ { kind: "crate", back: 11 } ])
    assert_equal true, response.parsed_body["can_accept"]
    checkout(returnables: [ { kind: "crate", back: 11 } ], accept_in_favor: "1")
    assert_response :ok
    assert_equal [ 0, 1 ], [ account.owed("crate"), account.in_favor("crate") ]
    get reviews_path(branch_id: "all")
    assert_select "td", /brought back 1 × Crate more than they owed/
  end

  test "the customer's account shows the count and receives, writes off and enters, each with its permission" do
    declare
    owe(8)
    owe(24, kind: "bottle")
    get customers_path
    assert_select "th", "Returnables"
    assert_select "td[data-returnables]", /Crate: 8\s+Glass bottle: 24/
    get account_customer_path(@lupita)
    assert_select "#returnable_counts tr[data-kind=crate] td", "8"
    assert_select "#returnable_counts tr[data-kind=bottle] td", "24"
    receive = css_select("#form_receive [name]").map { |field| field["name"] } - %w[authenticity_token commit]
    assert_equal %w[key kind quantity], receive # the names the form really sends
    assert_equal %w[key kind quantity reason], css_select("#form_write_off [name]").map { |field| field["name"] } - %w[authenticity_token commit]
    assert_equal %w[key kind direction quantity note], css_select("#form_entry [name]").map { |field| field["name"] } - %w[authenticity_token commit]

    post customer_returnables_receive_path(@lupita), params: { kind: "crate", quantity: "5", key: "once" }
    assert_redirected_to account_customer_path(@lupita, anchor: "returnables")
    assert_equal "Received 5 × Crate.", flash[:notice]
    post customer_returnables_receive_path(@lupita), params: { kind: "crate", quantity: "5", key: "once" }
    assert_equal 3, account.owed("crate"), "the same form sent twice receives once"

    post customer_returnables_write_off_path(@lupita), params: { kind: "crate", quantity: "1", reason: "" }
    assert_match "reason", flash[:alert]
    post customer_returnables_write_off_path(@lupita), params: { kind: "crate", quantity: "1", reason: "broken" }
    assert_match "Wrote off 1 × Crate; goes to review", flash[:notice]
    assert_equal [ 2, 8_500 ], [ account.owed("crate"), @lupita.balance_cents ]

    post customer_returnables_entry_path(@lupita), params: { kind: "bottle", direction: "in_favor", quantity: "30", note: "counted wrong last month" }
    assert_match "Entered 30 × Glass bottle", flash[:notice]
    assert_equal [ 0, 6 ], [ account.owed("bottle"), account.in_favor("bottle") ]
    post customer_returnables_entry_path(@lupita), params: { kind: "bottle", direction: "out", quantity: "1", note: "" }
    assert_match "needs a note", flash[:alert]

    get account_customer_path(@lupita)
    assert_select "#balance", "$85.00"
    assert_select "td", "1 × Crate written off"
    assert_select "#returnable_counts tr[data-kind=bottle] td", "6"
    assert_select "#returnable_history tr", 6 # the header and five movements
    assert_select "#returnable_history td", /Written off · broken/
    get customers_path
    assert_select "td[data-returnables]", /Crate: 2\s+Glass bottle: 6 in favour/
    get reviews_path(branch_id: "all")
    assert_select "td", /1 × Crate written off for Lupita's Diner/
    assert_select "td a[href=?]", account_customer_path(@lupita)
  end

  test "receiving more than owed opens the dialog; only someone allowed gets the way through" do
    declare
    owe(3)
    sign_in "supervisor"
    get account_customer_path(@lupita)
    assert_select "#form_entry", 0, "loose entries are not for the supervisor"
    assert_select "#form_receive select option", 1, "only what they owe can come back"
    post customer_returnables_receive_path(@lupita), params: { kind: "crate", quantity: "4" }
    assert_redirected_to account_customer_path(@lupita, over_kind: "crate", over_quantity: 4, anchor: "returnables")
    follow_redirect!
    assert_select "[data-dialog-open-value=true] dialog#more_than_owed p", "Crate: they owe 3 and 4 are coming back."
    assert_select "#form_accept_in_favor", 0
    post customer_returnables_receive_path(@lupita), params: { kind: "crate", quantity: "4", accept_in_favor: "1" }
    assert_equal [ 3, 0 ], [ account.owed("crate"), Review.count ], "stopped, and nothing reported"
    post customer_returnables_entry_path(@lupita), params: { kind: "crate", direction: "out", quantity: "1", note: "x" }
    assert_response :forbidden

    sign_in "admin"
    get account_customer_path(@lupita, over_kind: "crate", over_quantity: 4)
    accept = css_select("#form_accept_in_favor [name]").to_h { |field| [ field["name"], field["value"] ] }.except("authenticity_token", "commit")
    assert_equal({ "kind" => "crate", "quantity" => "4", "accept_in_favor" => "1" }, accept.except("key"))
    post customer_returnables_receive_path(@lupita), params: accept
    assert_equal [ 0, 1 ], [ account.owed("crate"), account.in_favor("crate") ]
    get account_customer_path(@lupita, over_kind: "crate", over_quantity: 4)
    assert_select "dialog#more_than_owed", 1, "four more would again be more than they owe"
    get account_customer_path(@lupita)
    assert_select "dialog#more_than_owed", 0

    sign_in "cashier"
    post customer_returnables_receive_path(@lupita), params: { kind: "crate", quantity: "1" }
    assert_response :forbidden, "this cashier has no returnables permission"
  end

  test "the product form marks a product as returnable and asks what it releases" do
    get edit_admin_product_path(@chicken)
    assert_select "#product_returnables input[type=checkbox][name='product[returnable]']"
    assert_select "#product_returnables table", 0, "no kinds declared yet"
    assert_match "No kinds are declared yet", response.body
    declare
    get edit_admin_product_path(@chicken)
    names = css_select("#product_returnables tbody tr:first-child [name]").map { |field| field["name"] } # the names the form really sends
    assert_equal %w[product[returnables_attributes][0][kind] product[returnables_attributes][0][from_quantity] product[returnables_attributes][0][per_quantity]], names
    assert_equal [ "", "Crate", "Glass bottle" ], css_select("select[name='#{names[0]}'] option").map(&:text)

    patch admin_product_path(@chicken), params: { "product[returnable]" => "1", names[0] => "", names[1] => "", names[2] => "" }
    assert_response :unprocessable_entity
    assert_match "must say what it releases", response.body
    patch admin_product_path(@chicken), params: { "product[returnable]" => "1", names[0] => "crate", names[1] => "15", names[2] => "" }
    assert_redirected_to admin_products_path
    release = @chicken.reload.returnables.sole
    assert_equal [ true, "crate", 15, nil ], [ @chicken.returnable?, release.kind, release.from_quantity, release.per_quantity ]

    get edit_admin_product_path(@chicken)
    assert_select "#product_returnables tbody tr", 3, "the saved line and two empty ones"
    assert_select "input[name='product[returnables_attributes][0][from_quantity]'][value='15.000']"
    assert_select "input[name='product[returnables_attributes][0][_destroy]']"
    patch admin_product_path(@chicken), params: { product: { returnables_attributes: { "0" => { id: release.id, _destroy: "1" } } } }
    assert_response :unprocessable_entity, "still marked, so it cannot be left with nothing"
    patch admin_product_path(@chicken), params: { product: { returnable: "0", returnables_attributes: { "0" => { id: release.id, _destroy: "1" } } } }
    assert_redirected_to admin_products_path
    assert_equal [ false, 0 ], [ @chicken.reload.returnable?, @chicken.returnables.count ]

    # The rule stops declaring a kind a product releases: the line stays, flagged.
    @ketchup.returnables.build(kind: "bottle", from_quantity: 1, per_quantity: 1)
    @ketchup.update!(returnable: true)
    declare('(returnable :crate "Crate" (allow))')
    get edit_admin_product_path(@ketchup)
    assert_select "select[name='product[returnables_attributes][0][kind]'] option[selected]", "bottle (not declared)"
  end

  test "the editor tries a kind without saving, offers the example and warns before dropping a kind in use" do
    get rule_edit_path("returnable")
    assert_response :ok
    assert_select "h2", "Returnables in Lisp"
    assert_select "textarea#code", /Out of the box this business has none/
    assert_select "aside code", "(owed-after)"
    assert_select "aside", /What it reads \(in pieces\)/
    assert_select "aside pre", /Up to ten crates out at a time/

    post rule_save_path("returnable"), params: { code: ReturnableRule::EXAMPLE, dry_run: "1", kind: "crate", owed: "9", leaving: "2" }
    assert_response :ok
    assert_select "#decision p", /It is stopped: .*too many/
    assert_select "select#kind option", 2
    assert_nil Rule.current("returnable"), "trying saves nothing"
    post rule_save_path("returnable"), params: { code: ReturnableRule::EXAMPLE, dry_run: "1", kind: "crate", owed: "9", leaving: "2", authorized: "1" }
    assert_select "#decision p", /They leave and it goes to review/
    post rule_save_path("returnable"), params: { code: '(returnable :crate "Crate" :deposit 5 (allow))', dry_run: "1" }
    assert_response :unprocessable_entity
    assert_match "option :deposit", response.body

    post rule_save_path("returnable"), params: { code: ReturnableRule::EXAMPLE }
    assert_redirected_to rule_edit_path("returnable")
    owe(5)
    post rule_save_path("returnable"), params: { code: ReturnableRule::EXAMPLE, dry_run: "1", customer_id: @lupita.id, kind: "crate", leaving: "6" }
    assert_select "#decision p", /It is stopped/
    assert_match "Crate: 5", response.body

    dropped = '(returnable :bottle "Glass bottle" (allow))'
    post rule_save_path("returnable"), params: { code: dropped }
    assert_response :ok
    assert_select "#warning", /1 customer still has a count of kinds this rule does not declare — :crate, 5 pieces/
    assert_equal ReturnableRule::EXAMPLE, Rule.current("returnable").code, "not saved until confirmed"
    post rule_save_path("returnable"), params: { code: dropped, confirmed: "1" }
    assert_equal dropped, Rule.current("returnable").code
    get account_customer_path(@lupita)
    assert_select "#returnable_counts .returnable-undeclared", /crate \(not declared\)/
    get customers_path
    assert_select "td[data-returnables] .returnable-undeclared", /crate \(not declared\): 5/

    file = RulesFile.export(business: "Test")
    assert_match ";;; hook: returnable (contract 1)", file
    get repl_path
    assert_select "code", "(returnables)"
  end
end
