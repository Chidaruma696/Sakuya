require "test_helper"

# The customer's account read on its own: charges settle oldest first, what is paid in excess
# stays in their favor, and the figures the credit rule reads follow from that.
class CustomerAccountTest < ActiveSupport::TestCase
  setup do
    @customer = Customer.create!(name: "Ana")
    @today = Date.new(2026, 11, 10)
  end

  def post(kind, cents, days_ago)
    sign = kind == "charge" ? 1 : -1
    @customer.credit_movements.create!(kind: kind, amount_cents: sign * cents, date: @today - days_ago, branch: branches(:store), user: users(:cashier))
  end

  def account = CustomerAccount.new(@customer, today: @today)

  test "an empty account owes nothing and has never paid" do
    assert_equal [ 0, 0, -1, nil ], [ account.balance_cents, account.open_charge_count, account.oldest_charge_days, account.days_since_payment ]
    assert_equal({ "0-30" => 0, "31-60" => 0, "61-90" => 0, "90+" => 0 }, account.age)
    assert_equal 0, account.overdue_cents(0)
  end

  test "payments settle the oldest charges first and partial ones leave the rest open" do
    post("charge", 10_000, 40)
    post("charge", 5_000, 20)
    post("charge", 2_000, 0)
    post("account_payment", 12_000, 10)
    assert_equal [ [ @today - 20, 3_000 ], [ @today, 2_000 ] ], account.open_charges
    assert_equal [ 5_000, 2, 20, 10 ], [ account.balance_cents, account.open_charge_count, account.oldest_charge_days, account.days_since_payment ]
    assert_equal({ "0-30" => 5_000, "31-60" => 0, "61-90" => 0, "90+" => 0 }, account.age)
    assert_equal [ 5_000, 3_000, 3_000, 0 ], [ -1, 0, 19, 20 ].map { |days| account.overdue_cents(days) }, "overdue means strictly older than N days"
  end

  test "money paid in excess stays in their favor and is used by the next charges" do
    post("account_payment", 7_000, 30)
    assert_equal [ -7_000, 0, -1 ], [ account.balance_cents, account.open_charge_count, account.oldest_charge_days ]
    post("charge", 5_000, 20)
    assert_equal [ -2_000, 0 ], [ account.balance_cents, account.open_charge_count ]
    post("charge", 5_000, 10)
    assert_equal [ [ @today - 10, 3_000 ] ], account.open_charges
    post("refund", 3_000, 5)
    assert_equal [ 0, 0, -1 ], [ account.balance_cents, account.open_charge_count, account.oldest_charge_days ]
  end

  test "the age buckets split at 30, 60 and 90 days, both ends included on the young side" do
    { 0 => "0-30", 30 => "0-30", 31 => "31-60", 60 => "31-60", 61 => "61-90", 90 => "61-90", 91 => "90+", 400 => "90+" }.each_with_index do |(days, _), i|
      post("charge", 100 + i, days)
    end
    assert_equal({ "0-30" => 201, "31-60" => 205, "61-90" => 209, "90+" => 213 }, account.age)
    assert_equal account.balance_cents, account.age.values.sum
  end

  test "whatever the history, what is open adds up to what is owed" do
    dice = Random.new(1_109)
    25.times do
      CreditMovement.where(customer: @customer).delete_all # straight in the database: the model refuses to delete
      Array.new(dice.rand(1..25)) { dice.rand(0..120) }.sort.reverse.each do |days_ago|
        dice.rand(5) < 3 ? post("charge", dice.rand(1..50_000), days_ago) : post(%w[account_payment refund].sample(random: dice), dice.rand(1..60_000), days_ago)
      end
      a = account
      assert_equal [ a.balance_cents, 0 ].max, a.open_charges.sum { |_, left| left }, "open charges add up to the debt"
      assert_equal a.open_charges.sum { |_, left| left }, a.age.values.sum
      assert_equal a.open_charges.sum { |_, left| left }, a.overdue_cents(-1)
      assert a.open_charges.all? { |_, left| left.positive? }
      assert_equal a.open_charges.map(&:first), a.open_charges.map(&:first).sort, "oldest first"
      assert_equal a.open_charges.empty?, a.oldest_charge_days == -1
      assert_equal @customer.balance_cents, a.balance_cents
    end
  end

  test "the account is a ledger: nothing in it is edited or deleted, and signs follow the kind" do
    charge = post("charge", 1_000, 1)
    assert_raises(ActiveRecord::ReadOnlyRecord) { charge.update!(amount_cents: 1) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { charge.destroy! }
    assert_raises(ActiveRecord::RecordInvalid) { @customer.credit_movements.create!(kind: "charge", amount_cents: -5, date: @today, branch: branches(:store), user: users(:cashier)) }
    assert_raises(ActiveRecord::RecordInvalid) { @customer.credit_movements.create!(kind: "account_payment", amount_cents: 5, date: @today, branch: branches(:store), user: users(:cashier)) }
    assert_raises(ActiveRecord::RecordInvalid) { @customer.credit_movements.create!(kind: "charge", amount_cents: 0, date: @today, branch: branches(:store), user: users(:cashier)) }
  end
end
