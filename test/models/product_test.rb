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

  test "matching finds by name or key whatever the case, accents and ñ included" do
    Product.create!(key: "JAL", name: "JALAPEÑO EN RAJAS", unit: "piece", price: 20)
    Product.create!(key: "PINA", name: "Piña miel", unit: "kg", price: 30)
    assert_equal %w[JAL], Product.matching("jalapeño").map(&:key)
    assert_equal %w[JAL], Product.matching("JALAPEÑO").map(&:key)
    assert_equal %w[PINA], Product.matching(" PIÑA ").map(&:key)
    assert_equal %w[CHKN], Product.matching("chicken").map(&:key)
    assert_equal %w[KETC], Product.matching("ketc").map(&:key), "by key too"
    assert_equal [], Product.matching("100%_").map(&:key), "wildcards are just text"
    assert_equal 4, Product.matching("").size
    products(:chicken).update!(active: false)
    assert_equal [], Product.active.matching("chicken")
  end

  test "a price that is not an amount is refused, not stored as zero" do
    assert_raises(Money::Invalid) { Product.new(key: "X", name: "X", unit: "kg").price = "12,50" }
  end
end
