require "test_helper"

class CreditTest < ActiveSupport::TestCase
  setup do
    @store = branches(:store)
    @cashier = users(:cashier)
    @ketchup = products(:ketchup)
    Inventory.move!(branch: @store, product: @ketchup, kind: "inflow", quantity: 20, user: @cashier)
    @lupita = Customer.create!(name: "Lupita's Diner", credit_limit: "100")
  end

  def on_account(quantity, customer: @lupita, user: @cashier, cash: 0)
    total = 4_200 * quantity
    Till.checkout!(branch: @store, user: user, key: SecureRandom.uuid, customer: customer, lines: [ { product_id: @ketchup.id, quantity: quantity } ],
                 payments: [ { payment_method: "cash", amount_cents: cash }, { payment_method: "credit", amount_cents: total - cash } ])
  end

  test "out of the box there is no credit: it is stopped and reported; without a customer it is not even attempted" do
    e = assert_raises(Till::Stopped) { on_account(1) }
    assert_match "this business does not sell on account", e.message
    assert_equal [ 0, 0 ], [ Sale.count, CreditMovement.count ]
    assert_match "On account for Lupita's Diner, $42.00, stopped", Review.last.reason
    assert_match "you must choose the customer", assert_raises(Till::Error) { on_account(1, customer: nil) }.message
  end

  test "with the limit rule credit is given up to the limit, the supervisor forces it and the account keeps the balance" do
    Rule.create!(hook: "credit", code: CreditRule::EXAMPLE, user: users(:admin))
    sale = on_account(2)
    assert_equal @lupita, sale.customer
    assert_equal 8_400, @lupita.balance_cents
    assert_equal [ "charge", "Sale #{sale.folio}" ], [ CreditMovement.last.kind, CreditMovement.last.reason ]
    assert_match "over their limit (owes $84.00, limit $100.00)", assert_raises(Till::Stopped) { on_account(1) }.message
    on_account(1, cash: 2_600)
    assert_equal 10_000, @lupita.balance_cents, "what is paid in cash does not go on account"
    assert_equal 2_600, Shift.opened_at(@store).cash_sales_cents
    forced = on_account(1, user: users(:supervisor))
    assert_equal [ forced, true ], [ Review.last.reviewable, Review.last.reason.include?("over their limit") ]
  end

  test "refunding what was sold on account lowers the debt before taking out cash" do
    Rule.create!(hook: "credit", code: "(allow)", user: users(:admin))
    sale = on_account(3, cash: 4_200) # 126 in total: 42 in cash and 84 on account
    shift = Shift.opened_at(@store)
    drawer = shift.expected_cash_cents
    d = Till.refund!(sale: sale, lines: [ { sale_line_id: sale.lines.first.id, quantity: 1 } ], reason: "broken", user: @cashier)
    assert_equal [ 4_200, 4_200 ], [ d.total_cents, d.on_account_cents ]
    assert_equal 4_200, @lupita.balance_cents
    assert_equal drawer, shift.expected_cash_cents, "nothing left the drawer"
    d = Till.refund!(sale: sale, lines: [ { sale_line_id: sale.lines.first.id, quantity: 2 } ], reason: "both broken", user: @cashier)
    assert_equal [ 8_400, 4_200 ], [ d.total_cents, d.on_account_cents ]
    assert_equal 0, @lupita.balance_cents
    assert_equal drawer - 4_200, shift.expected_cash_cents, "what was paid in cash goes out in cash"
  end

  test "the account knows what is overdue and the days without a payment" do
    CreditMovement.create!(customer: @lupita, branch: @store, user: @cashier, kind: "charge", amount_cents: 5_000, date: 40.days.ago.to_date)
    CreditMovement.create!(customer: @lupita, branch: @store, user: @cashier, kind: "charge", amount_cents: 3_000, date: 5.days.ago.to_date)
    CreditMovement.create!(customer: @lupita, branch: @store, user: @cashier, kind: "account_payment", amount_cents: -2_000, date: 2.days.ago.to_date)
    account = @lupita.account
    assert_equal 6_000, account.balance_cents
    assert_equal 3_000, account.overdue_cents(30), "the payment paid off part of the oldest charge"
    assert_equal 2, account.days_since_payment
    d = CreditRule.decide(CreditRule.data(@lupita, amount: 1, total: 1, authorized: false), code: '(if (> (overdue 30) 20) (reject "late") (allow))')
    assert_equal "late", d.reason
  end
end
