require "test_helper"

class RulesControllerTest < ActionDispatch::IntegrationTest
  setup { post login_path, params: { user: "admin", password: "secret12" } }

  test "the editor tests with a case, saves only what decides and restores" do
    get settings_path
    assert_select "a[href=?]", rule_edit_path("shift")
    get rule_edit_path("shift")
    assert_response :ok
    assert_select "textarea#code", /reject :over-limit/
    assert_select "input#expected[value='500.00']", 1, "by default, what the open session expects"

    code = '(if (< (difference) 0) (reject "missing") (allow))'
    post rule_save_path("shift"), params: { dry_run: "1", code: code, expected: "500", counted: "480" }
    assert_response :ok
    assert_select "#decision", /It is stopped: missing/
    assert_select "#made_up_yes[checked]", 0, "by default, the real session"
    assert_equal 0, Rule.count, "testing does not save"

    post rule_save_path("shift"), params: { code: "(allow" }
    assert_response :unprocessable_entity
    assert_select "p", /missing 1 closing parenthesis/
    post rule_save_path("shift"), params: { code: "(+ 1 2)" }
    assert_response :unprocessable_entity
    assert_select "p", /ended in 3/
    assert_equal 0, Rule.count

    post rule_save_path("shift"), params: { code: code }
    assert_redirected_to rule_edit_path("shift")
    assert_equal code, Rule.current("shift").code
    first = Rule.current("shift")
    post rule_save_path("shift"), params: { code: "(allow)" }
    post rule_restore_path("shift", first)
    assert_equal code, Rule.current("shift").code
    assert_equal 3, Rule.count
    assert_equal 0, Rule.for_hook("dashboard").count, "each hook keeps its own versions"
  end

  test "the price editor tests with a product from the catalogue" do
    get rule_edit_path("price")
    assert_response :ok
    assert_select "textarea#code", /reject :below-price/
    # Testing answers 200 without redirecting, and Turbo swallows those responses: the form goes without Turbo.
    assert_select "form#form_rule[data-turbo=false]"
    post rule_save_path("price"), params: { dry_run: "1", code: PriceRule::DEFAULT, product: "ketc", quantity: "1", price: "30" }
    assert_select "#decision", /It is stopped: below the regular price/
    assert_select "p", /Regular: \$42.00/
    post rule_save_path("price"), params: { dry_run: "1", code: "(if (authorized) (allow) (to-review \"x\"))", product: "KETC", price: "30", authorized: "1" }
    assert_select "#decision", /It is charged/
    post rule_save_path("price"), params: { code: "(allow)" }
    assert_equal "(allow)", Rule.current("price").code
    assert_nil Rule.current("shift")
    assert_raises(ActionController::UrlGenerationError) { rule_edit_path("nothing") }
  end

  test "withdrawals: the editor tests, and a custom rule sends large ones to review even with permission" do
    get rule_edit_path("withdrawal")
    assert_select "input#reason[value=?]", "safe"
    post rule_save_path("withdrawal"), params: { dry_run: "1", code: WithdrawalRule::DEFAULT, amount: "100" }
    assert_select "#decision", /It is stopped: permission to withdraw is needed/
    post rule_save_path("withdrawal"), params: { code: '(if (> (amount) 1000) (to-review "large withdrawal") (allow))' }
    post login_path, params: { user: "supervisor", password: "secret12" }
    post till_withdraw_path, params: { amount: "200", reason: "to the safe" }
    assert_equal 1, shifts(:store_open).withdrawals.count
    assert_equal 0, Review.count
    Inventory.move!(branch: branches(:store), product: products(:ketchup), kind: "inflow", quantity: 30, user: users(:admin))
    Till.checkout!(branch: branches(:store), user: users(:admin), key: "r", lines: [ { product_id: products(:ketchup).id, quantity: 30 } ], payments: [ { payment_method: "cash", amount_cents: 126_000 } ])
    post till_withdraw_path, params: { amount: "1200", reason: "bank" }
    assert_match "goes to review", flash[:notice]
    assert_equal "bank\nlarge withdrawal", Review.last.reason
  end

  test "stock: the editor tests, and a rule that lets the cashier through without permission leaves nothing to review" do
    get rule_edit_path("movement")
    assert_select "select#kind option[selected][value=waste]"
    post rule_save_path("movement"), params: { dry_run: "1", code: "(if (= (kind) :waste) (to-review \"waste\") (allow))", product: "KETC", kind: "waste" }
    assert_select "#decision", /It moves and goes to review: waste/
    post rule_save_path("movement"), params: { code: "(if (= (kind) :in) (allow) (reject :needs-permission))" }
    post rule_save_path("withdrawal"), params: { code: "(allow)" }
    post login_path, params: { user: "cashier", password: "secret12" }
    post movements_inventory_path, params: { product_id: products(:ketchup).id, kind: "inflow", quantity: "2", reason: "arrived" }
    assert_redirected_to kardex_inventory_path(product_id: products(:ketchup).id, branch_id: branches(:store).id)
    assert_no_match "review", Movement.last.reason
    post till_withdraw_path, params: { amount: "100", reason: "to the safe" }
    assert_equal 1, shifts(:store_open).withdrawals.count
    assert_equal 0, Review.count
  end

  test "invoices: the editor tests with the lock from Settings and disappears with the purchasing feature off" do
    post rule_save_path("invoice"), params: { dry_run: "1", code: InvoiceRule::DEFAULT, excess_items: "2", excess_value: "300" }
    assert_select "#decision", /It is stopped/
    assert_select "p", /lock in Settings › Purchases is on/
    post rule_save_path("invoice"), params: { dry_run: "1", code: InvoiceRule::EXAMPLE, excess_items: "1", excess_value: "80" }
    assert_select "#decision", /It is recorded and goes to review: Small excess/
    get rule_edit_path("invoice")
    assert_select "a[href=?]", rule_edit_path("invoice")
    Features.store!(Features::OPTIONAL - %w[purchases], check: false)
    get rule_edit_path("shift")
    assert_select "a[href=?]", rule_edit_path("invoice"), 0
  end

  test "each rule stores its contract version; an old one gets a warning and restoring it does not disguise it as new" do
    old = Rule.create!(hook: "shift", code: "(allow)", version: 0, user: users(:admin))
    get rule_edit_path("shift")
    assert_select "#notice_old", /version 0 of the hook and Sakuya is now on 1/
    post rule_save_path("shift"), params: { code: "(allow)" }
    assert_equal 1, Rule.current("shift").version
    get rule_edit_path("shift")
    assert_select "#notice_old", 0
    assert_select "span", /contract v0/
    post rule_restore_path("shift", old)
    assert_equal 0, Rule.current("shift").version
    dashboard = Rule.create!(hook: "dashboard", code: "(dashboard)", version: 0, user: users(:admin))
    get dashboard_edit_path
    assert_select "#notice_old"
    assert_equal 1, Rule.create!(hook: "dashboard", code: dashboard.code, user: users(:admin)).version
  end

  test "testing with real data: the open session, a sale gone through line by line and a recorded invoice" do
    users(:admin).update!(branch: branches(:store))
    store = branches(:store)
    Inventory.move!(branch: store, product: products(:ketchup), kind: "inflow", quantity: 5, user: users(:admin))
    sale = Till.checkout!(branch: store, user: users(:supervisor), key: "v", authorizer: users(:supervisor),
                         lines: [ { product_id: products(:ketchup).id, quantity: 1 }, { product_id: products(:ketchup).id, quantity: 1, price_cents: 3_000 } ],
                         payments: [ { payment_method: "cash", amount_cents: 7_200 } ])
    get rule_edit_path("shift")
    assert_select "input#expected[readonly][value='572.00']", 1, "float of 500 + 72 from the sale"
    post rule_save_path("shift"), params: { dry_run: "1", code: '(if (= (tickets) 1) (allow) (reject "no"))', counted: "572" }
    assert_select "#decision", /It closes/
    post rule_save_path("shift"), params: { dry_run: "1", code: '(if (= (tickets) 1) (allow) (reject "no"))', counted: "572", made_up: "1", expected: "100" }
    assert_select "#decision", /It is stopped: no/

    post rule_save_path("price"), params: { dry_run: "1", code: PriceRule::DEFAULT, sale: sale.folio.downcase }
    assert_select "#decision p", 2
    assert_select "#decision p", /at \$42.00 .* It is charged/m
    assert_select "#decision p", /at \$30.00 .* It is charged and goes to review.*has permission/m, "the supervisor authorized it: stopping means review"
    post rule_save_path("price"), params: { dry_run: "1", code: PriceRule::DEFAULT, sale: "NO-SUCH" }
    assert_select "p", /there is no sale NO-SUCH/

    supplier = Supplier.create!(name: "Farm", credit_days: 0)
    Purchases.invoice!(supplier: supplier, branch: store, user: users(:admin), folio: "F-9", date: Date.current,
                      lines: [ { product_id: products(:ketchup).id, quantity: "3", price: "30" } ])
    post rule_save_path("invoice"), params: { dry_run: "1", code: "(if (= (excess-value) 90) (reject :over-received) (allow))", invoice: "F-9" }
    assert_select "#decision", /It is stopped: invoicing more than received \(Ketchup 1 kg\)/
  end

  test "sales: the editor tests a made-up sale at a given hour and a real one" do
    get rule_edit_path("sale")
    assert_select "textarea#code", /\(allow\)/
    code = '(if (and (>= (hour) 22) (> (quantity-of "ketc") 0)) (reject "late") (allow))'
    post rule_save_path("sale"), params: { dry_run: "1", code: code, keys: "ketc, chkn", hour: "23", total: "50" }
    assert_select "#decision", /It is stopped: late/
    post rule_save_path("sale"), params: { dry_run: "1", code: code, keys: "ketc", hour: "9" }
    assert_select "#decision", /It is charged/
    post rule_save_path("sale"), params: { dry_run: "1", code: "(paid-with :card)", keys: "ketc" }
    assert_select "p", /paid-with takes a payment method/
  end

  test "receipts: without a delivery note nothing comes in (it is reported) and with permission it comes in for review; the editor tests" do
    post rule_save_path("receipt"), params: { dry_run: "1", code: ReceiptRule::EXAMPLE, arriving: "ketc 10, chkn 2.5", delivery_note: "" }
    assert_select "#decision", /It is stopped: No delivery note/
    post rule_save_path("receipt"), params: { dry_run: "1", code: "(if (= (quantity-of \"chkn\") 2.5) (allow) (reject \"no\"))", arriving: "ketc 10, chkn 2.5" }
    assert_select "#decision", /It comes in/
    post rule_save_path("receipt"), params: { code: '(if (= (delivery-note) "") (reject "no delivery note, no entry") (allow))' }
    supplier = Supplier.create!(name: "Farm", credit_days: 0)
    lines = { "0" => { product_id: products(:ketchup).id, quantity: "6" } }
    roles(:administrator).update!(permissions: Permission::KEYS.keys - [ "purchases.force_receipt" ])
    post receipts_path, params: { receipt: { supplier_id: supplier.id, delivery_note: "", lines_attributes: lines } }
    assert_match "no delivery note, no entry. It cannot come in like this", flash[:alert]
    assert_equal 0, Receipt.count
    assert_equal [ supplier, 25_200, true ], [ Review.last.reviewable, Review.last.value_cents, Review.last.stopped ]
    roles(:administrator).update!(permissions: [ "*" ])
    post receipts_path, params: { receipt: { supplier_id: supplier.id, delivery_note: "", lines_attributes: lines } }
    receipt = Receipt.last
    assert_redirected_to receipt_path(receipt)
    assert_equal [ receipt, "no delivery note, no entry" ], [ Review.last.reviewable, Review.last.reason ]
    assert_match "Receipt #{receipt.folio} from Farm", Review.last.description
  end

  test "credit: only with the customers feature; the editor tests with a real customer or a made-up one" do
    get rule_edit_path("shift")
    assert_select "a[href=?]", rule_edit_path("credit"), 0
    Features.store!(Features::OPTIONAL, check: false)
    customer = Customer.create!(name: "Lupita's Diner", credit_limit: "100")
    get rule_edit_path("credit")
    assert_select "a[href=?]", rule_edit_path("credit")
    assert_select "textarea#code", /reject :no-credit/
    post rule_save_path("credit"), params: { dry_run: "1", code: CreditRule::EXAMPLE, amount: "500", balance: "0", limit: "1000" }
    assert_select "#decision", /Credit given/
    post rule_save_path("credit"), params: { dry_run: "1", code: CreditRule::EXAMPLE, amount: "500", customer_id: customer.id }
    assert_select "#decision", /It is stopped: this sale takes them over their limit \(owes \$0.00, limit \$100.00\)/
    assert_select "p", /Owes \$0.00 · limit \$100.00/
  end

  test "without rules.edit you cannot get in" do
    post login_path, params: { user: "cashier", password: "secret12" }
    get rule_edit_path("shift")
    assert_response :forbidden
    post rule_save_path("shift"), params: { code: "(allow)" }
    assert_equal 0, Rule.count
  end
end
