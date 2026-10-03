require "test_helper"

class ReservationsTest < ActiveSupport::TestCase
  setup do
    Features.store!(Features::OPTIONAL, check: false)
    @store = branches(:store)
    @ketchup = products(:ketchup)
    Inventory.move!(branch: @store, product: @ketchup, kind: "inflow", quantity: 5, user: users(:admin))
    @lupita = Customer.create!(name: "Lupita's Diner")
  end

  def order(quantity, reserve: true)
    Order.create!(customer: @lupita, branch: @store, user: users(:cashier), reserve: reserve, lines_attributes: [ { product_id: @ketchup.id, quantity: quantity } ])
  end

  def sell(quantity, order: nil)
    Till.checkout!(branch: @store, user: users(:cashier), key: SecureRandom.uuid, order: order, lines: [ { product_id: @ketchup.id, quantity: quantity } ],
                 payments: [ { payment_method: "cash", amount_cents: 100_000 } ])
  end

  test "an order holds stock: what is held is neither sold nor transferred, except when checking out that order" do
    p = order(3)
    assert_equal 3, Reservations.reserved_for(@store, @ketchup)
    assert_equal 2, Reservations.available(@store, @ketchup)
    sell(2)
    e = assert_raises(Till::Error) { sell(1) }
    assert_match "there are 3 pc, but 3 pc is held for orders; available 0 pc", e.message
    assert_match "held for orders", assert_raises(Reservations::Error) {
      StockTransfer.register!(origin: @store, destination: branches(:head_office), user: users(:admin), lines: [ { product_id: @ketchup.id, quantity: 1 } ])
    }.message
    sell(3, order: p)
    p.deliver!(Sale.last)
    assert_equal 0, Reservations.reserved_for(@store, @ketchup), "once delivered it no longer holds stock"
  end

  test "an order that is not covered is not saved; without holding it is, and cancelling releases" do
    order(4)
    e = assert_raises(ActiveRecord::RecordInvalid) { order(2) }
    assert_match "you ask for 2 pc and 1 pc is available", e.message
    future = order(20, reserve: false)
    assert_equal 4, Reservations.reserved_for(@store, @ketchup), "without holding it does not count"
    Order.first.cancel!(reason: "no longer needed")
    assert_equal 0, Reservations.reserved_for(@store, @ketchup)
    assert future.persisted?
  end

  test "waste can touch held stock: it records something that already happened" do
    order(5)
    Inventory.move!(branch: @store, product: @ketchup, kind: "waste", quantity: 1, user: users(:admin))
    assert_equal 4, StockLevel.quantity_for(@store, @ketchup)
    assert_equal(-1, Reservations.available(@store, @ketchup))
  end

  test "with the customers feature off there is no held stock" do
    order(3)
    Features.store!(Features::OPTIONAL - %w[customers], check: false)
    assert_equal({}, Reservations.by_product(@store))
  end

  test "restocking counts what is available, not what is held" do
    Minimum.create!(branch: @store, product: @ketchup, minimum: 3, maximum: 6)
    assert_empty Minimum.suggested(@store), "there are 5"
    order(4)
    assert_equal [ [ @ketchup, 5 ] ], Minimum.suggested(@store), "1 available: 5 short of the maximum"
  end
end
