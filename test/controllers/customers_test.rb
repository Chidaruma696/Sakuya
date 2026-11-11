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

  test "the credit type and the cut-off day are chosen on the form, from what the credit rule declares" do
    get new_customer_path
    assert_select "form.form select", 0, "no credit rule, nothing to choose"
    Rule.create!(hook: "credit", code: CreditRule::EXAMPLE, user: users(:admin))
    get new_customer_path
    type, day = css_select("form.form select").map { |s| s["name"] } # the names the form really sends
    assert_equal [ "customer[credit_type]", "customer[cutoff_day]" ], [ type, day ]
    assert_equal [ "— none —", "Cash only", "Note by note", "Credit limit", "Weekly", "Cash, paying down", "Special" ], css_select("select[name='#{type}'] option").map(&:text)
    assert_equal [ "", "5" ], css_select("select[name='#{day}'] option").to_a.values_at(0, 6).map { |o| o["value"] }

    post customers_path, params: { "customer[name]" => "Lupita's Diner", type => "note-by-note", day => "5" }
    assert_redirected_to customers_path
    customer = Customer.last
    assert_equal [ "note-by-note", 5, :friday ], [ customer.credit_type, customer.cutoff_day, customer.cutoff_keyword ]
    post customers_path, params: { "customer[name]" => "No such type", type => "invented" }
    assert_response :unprocessable_entity
    Customer.create!(name: "Walk-in")

    get customers_path
    assert_select "th", "Credit type"
    assert_select "td", /Note by note\s+Fri/
    get account_customer_path(customer)
    assert_select "#credit_type", /Note by note\s+Fri/
    get edit_customer_path(customer)
    assert_select "select[name='#{type}'] option[selected]", "Note by note"
    assert_select "select[name='#{day}'] option[selected]", "Friday"

    # The rule stops declaring it: the customer keeps it, flagged, and the form still offers it.
    Rule.create!(hook: "credit", code: '(credit-type :cash "Cash only" (reject :cash-only))', user: users(:admin))
    get customers_path
    assert_select "td .credit-type-unknown", /note-by-note \(not declared\)/
    get edit_customer_path(customer)
    assert_select "select[name='#{type}'] option[selected]", "note-by-note (not declared)"
    patch customer_path(customer), params: { "customer[phone]" => "555", type => "note-by-note", day => "" }
    assert_redirected_to customers_path
    assert_equal [ "note-by-note", nil, "555" ], customer.reload.then { |c| [ c.credit_type, c.cutoff_day, c.phone ] }
    patch customer_path(customer), params: { type => "" }
    assert_nil customer.reload.credit_type
  end

  test "with the feature off nobody gets in, and neither does the cashier without permission" do
    Features.store!(Features::OPTIONAL - %w[customers returnables], check: false)
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
