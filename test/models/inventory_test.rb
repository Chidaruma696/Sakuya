require "test_helper"

class InventoryTest < ActiveSupport::TestCase
  setup do
    @store = branches(:store)
    @chicken = products(:chicken)
    @cashier = users(:cashier)
  end

  test "an inflow creates the stock level and leaves the balance in the kardex" do
    m = Inventory.move!(branch: @store, product: @chicken, kind: "inflow", quantity: "12.5", user: @cashier, reason: "test")
    assert_equal BigDecimal("12.5"), StockLevel.quantity_for(@store, @chicken)
    assert_equal BigDecimal("12.5"), m.balance
    Inventory.move!(branch: @store, product: @chicken, kind: "sale", quantity: "2.250", user: @cashier)
    assert_equal BigDecimal("10.25"), StockLevel.quantity_for(@store, @chicken)
  end

  test "never leaves the stock level negative" do
    Inventory.move!(branch: @store, product: @chicken, kind: "inflow", quantity: 1, user: @cashier)
    assert_raises(Inventory::OutOfStock) do
      Inventory.move!(branch: @store, product: @chicken, kind: "sale", quantity: "1.001", user: @cashier)
    end
    assert_equal BigDecimal("1"), StockLevel.quantity_for(@store, @chicken)
    assert_equal 1, Movement.count
  end

  test "rejects zero or negative quantities and unknown kinds" do
    assert_raises(ArgumentError) { Inventory.move!(branch: @store, product: @chicken, kind: "inflow", quantity: 0, user: @cashier) }
    assert_raises(ArgumentError) { Inventory.move!(branch: @store, product: @chicken, kind: "gift", quantity: 1, user: @cashier) }
  end

  test "stock levels are per branch" do
    Inventory.move!(branch: branches(:head_office), product: @chicken, kind: "inflow", quantity: 100, user: users(:admin))
    assert_equal BigDecimal("0"), StockLevel.quantity_for(@store, @chicken)
  end

  test "the kardex cannot be edited or deleted" do
    m = Inventory.move!(branch: @store, product: @chicken, kind: "inflow", quantity: 1, user: @cashier)
    assert_raises(ActiveRecord::ReadOnlyRecord) { m.update!(quantity: 5) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { m.destroy! }
  end
end
