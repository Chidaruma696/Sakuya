require "test_helper"

# Stock transfers and warehouses: stock goes out and comes in within the same transaction; from a
# warehouse only to the head office; cancelling brings the goods back; a warehouse has no till.
class StockTransferTest < ActiveSupport::TestCase
  setup do
    @head_office = branches(:head_office)
    @store = branches(:store)
    @admin = users(:admin)
    @chicken = products(:chicken)
    @cold = Branch.create!(code: "CLD", name: "Cold storage", kind: "warehouse", cash_limit_cents: 1)
    Inventory.move!(branch: @head_office, product: @chicken, kind: "inflow", quantity: 5000, user: @admin)
  end

  def transfer_stock(origin, destination, quantity, **extra)
    StockTransfer.register!(origin: origin, destination: destination, user: @admin, lines: [ { product_id: @chicken.id, quantity: quantity, boxes: 10 } ], **extra)
  end

  test "goes out and comes in within the same transaction, with a TG folio and idempotent by key" do
    t = transfer_stock(@head_office, @cold, 3000, key: "c1")
    assert_match(/\ATG-/, t.folio)
    assert_equal 2000, StockLevel.quantity_for(@head_office, @chicken)
    assert_equal 3000, StockLevel.quantity_for(@cold, @chicken)
    assert_equal t, transfer_stock(@head_office, @cold, 3000, key: "c1")
    assert_equal 2000, StockLevel.quantity_for(@head_office, @chicken)
    assert_equal %w[outflow inflow], t.movements.order(:id).pluck(:kind)
    assert_raises(Inventory::OutOfStock) { transfer_stock(@head_office, @cold, 9999) }
  end

  test "from an external warehouse goods only go to the head office" do
    transfer_stock(@head_office, @cold, 3000)
    assert_raises(StockTransfer::Error) { transfer_stock(@cold, @store, 100) }
    transfer_stock(@cold, @head_office, 1000)
    assert_equal 3000, StockLevel.quantity_for(@head_office, @chicken)
  end

  test "cancelling brings the goods back to the origin" do
    t = transfer_stock(@head_office, @cold, 3000)
    t.cancel!(reason: "wrong truck", user: @admin)
    assert t.cancelled?
    assert_equal 5000, StockLevel.quantity_for(@head_office, @chicken)
    assert_equal 0, StockLevel.quantity_for(@cold, @chicken)
    assert_raises(StockTransfer::Error) { t.cancel!(reason: "once more", user: @admin) }
  end

  test "a warehouse has no till" do
    assert_raises(ArgumentError) { Shift.open!(branch: @cold, user: @admin, float_cents: 0) }
  end
end
