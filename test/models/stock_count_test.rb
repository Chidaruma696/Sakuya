require "test_helper"

class StockCountTest < ActiveSupport::TestCase
  setup do
    @store = branches(:store)
    @supervisor = users(:supervisor)
    @cashier = users(:cashier)
    Inventory.move!(branch: @store, product: products(:chicken), kind: "inflow", quantity: 5, user: @supervisor)
    Inventory.move!(branch: @store, product: products(:ketchup), kind: "inflow", quantity: 10, user: @supervisor)
  end

  test "it opens with the stock level, each scan adds one piece and anything sold by the kilo is typed in" do
    c = StockCount.open!(branch: @store, user: @supervisor, responsible: @cashier)
    assert_match(/\AK-\d{5}\z/, c.folio)
    assert_equal({ products(:chicken) => BigDecimal("5"), products(:ketchup) => BigDecimal("10") }, c.lines.to_h { |l| [ l.product, l.system ] })
    2.times { c.scan!(products(:ketchup)) }
    assert_raises(ArgumentError) { c.scan!(products(:chicken)) }
    c.count_manual!(products(:chicken), "2.5")
    c.count_manual!(products(:chicken), "2")
    assert_equal BigDecimal("2"), c.lines.find_by(product: products(:chicken)).counted
    assert_equal BigDecimal("2"), c.lines.find_by(product: products(:ketchup)).counted
    assert_raises(ArgumentError) { StockCount.open!(branch: @store, user: @supervisor, responsible: @cashier) }
  end

  test "a partial count only touches what was chosen and rejects what is outside it; the cyclic count warns when it is due" do
    assert_raises(ArgumentError) { StockCount.open!(branch: @store, user: @supervisor, responsible: @cashier, products: []) }
    c = StockCount.open!(branch: @store, user: @supervisor, responsible: @cashier, products: [ products(:ketchup) ])
    assert c.partial?
    assert_equal [ products(:ketchup) ], c.lines.map(&:product)
    assert_raises(ArgumentError) { c.count_manual!(products(:chicken), 1) }
    c.count_manual!(products(:ketchup), 7)
    c.close!(user: @supervisor)
    assert_equal BigDecimal("7"), StockLevel.quantity_for(@store, products(:ketchup))
    assert_equal BigDecimal("5"), StockLevel.quantity_for(@store, products(:chicken)), "the chicken was not touched"
    assert_equal 1, c.lines.count

    assert_not StockCount.overdue?(@store), "without an interval it is never due"
    @store.update!(count_interval_days: 7)
    assert_not StockCount.overdue?(@store), "one was just closed"
    c.update_columns(closed_at: 8.days.ago)
    assert StockCount.overdue?(@store)
    assert StockCount.overdue?(branches(:head_office).tap { |b| b.update!(count_interval_days: 1) }), "it has never counted"
  end

  test "on closing the count rules: it adjusts inventory and charges the shortage" do
    c = StockCount.open!(branch: @store, user: @supervisor, responsible: @cashier)
    c.count_manual!(products(:chicken), 2)
    c.count_manual!(products(:ketchup), 8)
    c.close!(user: @supervisor)
    assert_equal "closed", c.status
    assert_equal BigDecimal("2"), StockLevel.quantity_for(@store, products(:chicken))
    assert_equal BigDecimal("8"), StockLevel.quantity_for(@store, products(:ketchup))
    # 3 kg of chicken (3 × 129) and 2 ketchup (2 × 42) are missing = 387 + 84 = 471
    assert_equal 47_100, c.shortage_cents
    assert_equal 0, c.surplus_cents
    charge = Charge.last
    assert_equal @cashier, charge.user
    assert_equal 47_100, charge.amount_cents
    assert_match "Chicken breast", charge.detail
    assert_equal 2, Movement.where(reference: c).count
    assert_raises(ArgumentError) { c.close!(user: @supervisor) }
    charge.resolve!("paid", user: @supervisor)
    assert_equal "paid", charge.status
    assert_raises(ArgumentError) { charge.resolve!("forgiven", user: @supervisor) }
  end

  test "a surplus creates no charge and an exact count moves nothing" do
    c = StockCount.open!(branch: @store, user: @supervisor, responsible: @cashier)
    c.count_manual!(products(:chicken), 5)
    11.times { c.scan!(products(:ketchup)) }
    c.close!(user: @supervisor)
    assert_equal 0, c.shortage_cents
    assert_equal 4_200, c.surplus_cents
    assert_equal 0, Charge.count
    assert_equal BigDecimal("11"), StockLevel.quantity_for(@store, products(:ketchup))
    assert_equal 1, Movement.where(reference: c).count, "the chicken matched and did not move"
  end
end
