require "test_helper"

# Whatever gets typed, no screen answers with a 500: it says what is wrong and nothing is saved.
class BadInputTest < ActionDispatch::IntegrationTest
  def sign_in(user) = post(login_path, params: { user: user, password: "secret12" })

  def assert_bounced(message = /is not an amount/)
    assert_response :redirect
    assert_match message, flash[:alert]
  end

  test "amounts that are not amounts, on every screen that takes money" do
    sign_in "admin"
    users(:admin).update!(branch: branches(:store))
    Setting.store!("features.customers" => "1")
    customer = Customer.create!(name: "Ana")
    supplier = Supplier.create!(name: "Ketchup & Co")

    post till_withdraw_path, params: { amount: "12,50", reason: "to the safe" }
    assert_bounced
    post till_close_path, params: { counted: "five hundred" }
    assert_bounced
    assert shifts(:store_open).reload.open?
    post pay_account_customer_path(customer), params: { amount: "1,000", payment_method: "cash" }
    assert_bounced
    post pay_account_path(supplier), params: { amount: "abc", payment_method: "transfer" }
    assert_bounced
    post customers_path, params: { customer: { name: "Luis", credit_limit: "2,000" } }
    assert_bounced
    patch customer_path(customer), params: { customer: { name: "Ana", credit_limit: "lots" } }
    assert_bounced
    post admin_products_path, params: { product: { key: "NEW", name: "New", unit: "kg", price: "12,50" } }
    assert_bounced
    patch admin_product_path(products(:ketchup)), params: { product: { name: "Ketchup 1 kg" }, prices: { branches(:store).id => "4o" } }
    assert_bounced

    assert_equal [ 0, 0, 0 ], [ Withdrawal.count, AccountPayment.count, SupplierPayment.count ]
    assert_equal [ 1, 0 ], [ Customer.count, customer.reload.credit_limit_cents ]
    assert_nil Product.find_by(key: "NEW")
    assert_equal 4_200, products(:ketchup).reload.price_cents_for(branches(:store))
  end

  test "the rule editor's test case takes odd amounts without breaking" do
    sign_in "admin"
    get rule_edit_path("shift", counted: "1,000", made_up: "1")
    assert_bounced
    post rule_save_path("withdrawal"), params: { code: "(allow)", dry_run: "1", amount: "ten", made_up: "1" }
    assert_bounced
    post rule_save_path("credit"), params: { code: "(allow)", amount: "5,5" }
    assert_bounced
    assert_equal 0, Rule.count
    get rule_edit_path("shift", counted: "1000", made_up: "1")
    assert_response :ok
  end

  test "a movement with a quantity that is not a positive number moves nothing and reports nothing" do
    sign_in "cashier"
    [ "-5", "0", "abc", "", "NaN", "Infinity", "1e15", "0.0001" ].each do |quantity|
      post movements_inventory_path, params: { product_id: products(:chicken).id, kind: "waste", quantity: quantity, reason: "spoiled" }
      assert_response :unprocessable_entity, quantity.inspect
      assert_match "must be greater than zero", response.body, quantity.inspect
    end
    post movements_inventory_path, params: { product_id: products(:ketchup).id, kind: "waste", quantity: "0.5", reason: "half a bottle" }
    assert_response :unprocessable_entity
    assert_match "sold in whole pieces", response.body
    assert_equal [ 0, 0 ], [ Review.count, Movement.count ]
  end

  test "the till answers an odd ticket with its error as JSON" do
    sign_in "cashier"
    ketchup = products(:ketchup)
    Inventory.move!(branch: branches(:store), product: ketchup, kind: "inflow", quantity: 5, user: users(:cashier))
    cash = [ { payment_method: "cash", amount_cents: 99_999 } ].to_json
    { "not json" => "{", "quantity in words" => [ { product_id: ketchup.id, quantity: "two" } ].to_json,
      "endless quantity" => [ { product_id: ketchup.id, quantity: "Infinity" } ].to_json,
      "unknown product" => [ { product_id: 0, quantity: 1 } ].to_json, "empty ticket" => "[]" }.each do |name, lines|
      post till_checkout_path, params: { key: SecureRandom.uuid, lines: lines, payments: cash }
      assert_response :unprocessable_entity, name
      assert JSON.parse(response.body)["error"].present?, name
    end
    post till_checkout_path, params: { key: SecureRandom.uuid, lines: [ { product_id: ketchup.id, quantity: 1 } ].to_json, payments: cash, sold_at: "yesterday" }
    assert_response :unprocessable_entity
    assert_equal 0, Sale.count
  end

  test "a refund with letters in the quantity goes back to the ticket with the reason" do
    sign_in "cashier"
    ketchup = products(:ketchup)
    Inventory.move!(branch: branches(:store), product: ketchup, kind: "inflow", quantity: 5, user: users(:cashier))
    sale = Till.checkout!(branch: branches(:store), user: users(:cashier), key: "r1", lines: [ { product_id: ketchup.id, quantity: 2 } ],
                         payments: [ { payment_method: "cash", amount_cents: 8_400 } ])
    post till_create_refund_path, params: { sale_id: sale.id, code: sale.folio, reason: "dented", lines: { sale.lines.first.id => "1abc" } }
    assert_redirected_to till_refund_path(code: sale.folio)
    assert_match "invalid quantity", flash[:alert]
    post till_create_refund_path, params: { sale_id: sale.id, code: sale.folio, reason: "dented", lines: { sale.lines.first.id => "0.5" } }
    assert_match "whole pieces", flash[:alert]
    assert_equal 0, Refund.count
  end
end
