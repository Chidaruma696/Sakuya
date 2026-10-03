require "test_helper"

class CustomersTest < ActionDispatch::IntegrationTest
  setup do
    Features.store!(Features::OPTIONAL, check: false)
    post login_path, params: { user: "admin", password: "secret12" }
  end

  test "adding, searching and editing customers, with their tab on the ribbon" do
    get customers_path
    assert_select "a[href=?]", new_customer_path
    assert_match "No customers yet", response.body
    post customers_path, params: { customer: { name: "" } }
    assert_response :unprocessable_entity
    post customers_path, params: { customer: { name: "Lupita's Diner", phone: "555 123", credit_limit: "1500" } }
    assert_redirected_to customers_path
    customer = Customer.last
    assert_equal 150_000, customer.credit_limit_cents
    get customers_path(q: "lupi")
    assert_select "td", /Lupita's Diner/
    get customers_path(q: "nobody")
    assert_select "td", { text: /Lupita's Diner/, count: 0 }
    patch customer_path(customer), params: { customer: { active: "0" } }
    assert_not customer.reload.active
  end

  test "with the feature off nobody gets in, and neither does the cashier without permission" do
    Features.store!(Features::OPTIONAL - %w[customers], check: false)
    get customers_path
    assert_response :not_found
    assert_match "Customers", response.body
    get root_path
    assert_select "nav a[href=?]", customers_path, 0
    Features.store!(Features::OPTIONAL, check: false)
    post login_path, params: { user: "cashier", password: "secret12" }
    get customers_path
    assert_response :forbidden
  end

  test "account statement: a payment goes into the drawer, lowers the balance and the aging shows" do
    users(:admin).update!(branch: branches(:store))
    customer = Customer.create!(name: "Lupita's Diner")
    CreditMovement.create!(customer: customer, branch: branches(:store), user: users(:admin), kind: "charge", amount_cents: 30_000, date: 45.days.ago.to_date, reason: "Old sale")
    CreditMovement.create!(customer: customer, branch: branches(:store), user: users(:admin), kind: "charge", amount_cents: 10_000, date: Date.current, reason: "New sale")
    get account_customer_path(customer)
    assert_select "#balance", "$400.00"
    assert_select ".card", /31-60 days\s*\$300.00/
    shift = Shift.opened_at(branches(:store))
    drawer = shift.expected_cash_cents
    post pay_account_customer_path(customer), params: { amount: "250", payment_method: "cash" }
    assert_redirected_to account_customer_path(customer)
    assert_match "they now owe $150.00", flash[:notice]
    assert_equal drawer + 25_000, shift.expected_cash_cents
    post pay_account_customer_path(customer), params: { amount: "50", payment_method: "transfer" }
    assert_equal drawer + 25_000, shift.expected_cash_cents, "a transfer does not go into the drawer"
    assert_equal 10_000, customer.balance_cents
    get account_customer_path(customer)
    assert_select ".card", /31-60 days\s*\$0.00/
    assert_select "td", /Payment AB-/
    post pay_account_customer_path(customer), params: { amount: "0" }
    assert_match "greater than zero", flash[:alert]
    get till_summary_path(shift)
    assert_match "Customer payments", response.body
  end
end
