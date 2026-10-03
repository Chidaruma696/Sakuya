require "test_helper"

class ProductTest < ActiveSupport::TestCase
  test "assigns the PLU after the highest one, never below 90000" do
    p = Product.create!(key: "NEW", name: "New", unit: "kg", price: 10)
    assert_equal 90003, p.plu
  end

  test "the price is stored in whole cents" do
    p = Product.new(key: "X", name: "X", unit: "kg")
    p.price = "129.999"
    assert_equal 13000, p.price_cents
    assert_equal BigDecimal("130"), p.price
  end

  test "rejects an invalid unit and price" do
    p = Product.new(key: "X", name: "X", unit: "gallon", price_cents: -1)
    assert_not p.valid?
    assert p.errors[:unit].any?
    assert p.errors[:price_cents].any?
  end

  test "supplier barcodes are normalized to digits and never repeat" do
    c = products(:chicken).product_barcodes.create(code: "750 1006 559019")
    assert_not c.persisted?, "the ketchup's barcode already exists"
    c2 = products(:chicken).product_barcodes.create!(code: " 0012345678905 ")
    assert_equal "0012345678905", c2.code
  end
end

class UnitsTest < ActiveSupport::TestCase
  test "kilo, litre and metre take fractions; the piece is whole" do
    liter = Product.create!(key: "MILK", name: "Bulk milk", unit: "liter", price: 22)
    meter = Product.create!(key: "CABL", name: "Cable", unit: "meter", price: 9)
    assert liter.fractional? && meter.fractional? && products(:chicken).fractional?
    assert_not products(:ketchup).fractional?
    assert_equal 3, liter.decimals
    assert_equal "l", liter.short_unit
    assert_equal "m", meter.short_unit
    assert_not liter.kg?, "the scale only weighs kilos"
    Inventory.move!(branch: branches(:store), product: liter, kind: "inflow", quantity: 10, user: users(:admin))
    sale = Till.checkout!(branch: branches(:store), user: users(:admin), key: "lt1", lines: [ { product_id: liter.id, quantity: "1.5" } ],
                         payments: [ { payment_method: "cash", amount_cents: 3_300 } ])
    assert_equal BigDecimal("1.5"), sale.lines.first.quantity
  end
end
