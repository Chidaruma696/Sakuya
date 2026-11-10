require "test_helper"

# The corners of the till: odd quantities, cents that round the wrong way and rules that break.
class TillEdgeCasesTest < ActiveSupport::TestCase
  setup do
    @store = branches(:store)
    @cashier = users(:cashier)
    @chicken = products(:chicken)
    @ketchup = products(:ketchup)
    Inventory.move!(branch: @store, product: @chicken, kind: "inflow", quantity: 10, user: @cashier)
    Inventory.move!(branch: @store, product: @ketchup, kind: "inflow", quantity: 5, user: @cashier)
  end

  def checkout(lines, payments = nil, **extra)
    Till.checkout!(branch: @store, user: @cashier, lines: lines, key: SecureRandom.uuid,
                 payments: payments || [ { payment_method: "cash", amount_cents: 1_000_000 } ], **extra)
  end

  def refund(sale, quantity, line: sale.lines.first)
    Till.refund!(sale: sale, lines: [ { sale_line_id: line.id, quantity: quantity } ], reason: "changed their mind", user: @cashier)
  end

  test "a quantity that is not a positive number is refused by name, whatever was typed" do
    [ "abc", "", nil, "0", "-1", "0.0004", "NaN", "Infinity", "-Infinity", "1e12", "1,5", "1 kg" ].each do |quantity|
      error = assert_raises(Till::Error, quantity.inspect) { checkout([ { product_id: @chicken.id, quantity: quantity } ]) }
      assert_equal "Chicken breast: invalid quantity", error.message, quantity.inspect
    end
    assert_equal 0, Sale.count
    assert_equal BigDecimal("10"), StockLevel.quantity_for(@store, @chicken)
  end

  test "quantities are kept to three decimals and the amount rounds half up" do
    sale = checkout([ { product_id: @chicken.id, quantity: "0.33349" }, { product_id: @chicken.id, quantity: "1.0005" } ])
    assert_equal [ BigDecimal("0.333"), BigDecimal("1.001") ], sale.lines.order(:id).map(&:quantity)
    assert_equal [ 4_296, 12_913 ], sale.lines.order(:id).map(&:amount_cents) # 42.957 → 42.96; 129.129 → 129.13
    assert_equal 17_209, sale.total_cents
  end

  test "the price floor is exact: the floor itself can be charged and one cent less cannot" do
    Setting.store!("till.price_floor" => "55")
    @ketchup.update!(price_cents: 100) # 55 % of $1.00 is exactly $0.55 (in floating point, 55.00000000000001)
    at_floor = checkout([ { product_id: @ketchup.id, quantity: 1, price_cents: 55 } ], nil, authorizer: users(:supervisor))
    assert_equal 55, at_floor.total_cents
    error = assert_raises(Till::Error) { checkout([ { product_id: @ketchup.id, quantity: 1, price_cents: 54 } ], nil, authorizer: users(:supervisor)) }
    assert_match "cannot go below 55 % of the catalog ($0.55)", error.message
    # A floor that does not land on a whole cent rounds up: 55 % of $0.99 is 54.45 → $0.55.
    @ketchup.update!(price_cents: 99)
    assert_raises(Till::Error) { checkout([ { product_id: @ketchup.id, quantity: 1, price_cents: 54 } ], nil, authorizer: users(:supervisor)) }
    assert_equal 55, checkout([ { product_id: @ketchup.id, quantity: 1, price_cents: 55 } ], nil, authorizer: users(:supervisor)).total_cents
  end

  test "every floor from 1 to 100 % lets its own exact price through" do
    @ketchup.update!(price_cents: 100)
    Inventory.move!(branch: @store, product: @ketchup, kind: "inflow", quantity: 200, user: @cashier)
    (1..100).each do |floor|
      Setting.store!("till.price_floor" => floor.to_s)
      sale = checkout([ { product_id: @ketchup.id, quantity: 1, price_cents: floor } ], nil, authorizer: users(:supervisor))
      assert_equal floor, sale.total_cents, "floor #{floor} %"
    end
  end

  test "refunding a line in parts never adds up to more than was charged for it" do
    @chicken.update!(price_cents: 333)
    sale = checkout([ { product_id: @chicken.id, quantity: "1.5" } ]) # 1.5 × 3.33 = 4.995 → $5.00
    assert_equal 500, sale.total_cents
    amounts = 3.times.map { refund(sale, "0.5").total_cents } # each half kilo alone is 1.665 → $1.67
    assert_equal [ 167, 167, 166 ], amounts
    assert_equal 500, sale.total_refunded_cents
    assert_equal 0, sale.balance_cents
    assert_equal "refunded", sale.reload.status
    assert_equal 50_000, shifts(:store_open).expected_cash_cents, "the drawer ends where it started"
  end

  test "the part that closes a line also covers what earlier parts rounded down" do
    @chicken.update!(price_cents: 333)
    sale = checkout([ { product_id: @chicken.id, quantity: "0.004" } ]) # 0.004 × 3.33 = 1.332 → $0.01
    assert_equal 1, sale.total_cents
    assert_equal 0, refund(sale, "0.001").total_cents # 0.333 of a cent rounds to nothing
    assert_equal 1, refund(sale, "0.003").total_cents
    assert_equal "refunded", sale.reload.status
  end

  test "a refund takes whole pieces of what is sold by the piece, and only real quantities" do
    sale = checkout([ { product_id: @ketchup.id, quantity: 2 } ])
    assert_match "sold in whole pieces", assert_raises(Till::Error) { refund(sale, "0.5") }.message
    [ "1abc", "abc", "NaN", "Infinity", "0", "-1" ].each do |quantity|
      assert_match "invalid quantity", assert_raises(Till::Error, quantity) { refund(sale, quantity) }.message
    end
    assert_match "at most 2.0 can be returned", assert_raises(Till::Error) { refund(sale, 3) }.message
    assert_equal 0, Refund.count
    assert_equal BigDecimal("3"), StockLevel.quantity_for(@store, @ketchup)
  end

  test "a rule that breaks inside a native does not stop the till: the built-in one decides and it is reported" do
    [ "(take -1 (list 1 2))", %((round (price) "two")), "(define (1 x) 2)", "(nth (list 1) 99999999999999999999999999)" ].each do |code|
      Rule.create!(hook: "price", user: users(:admin), code: code)
      sale = checkout([ { product_id: @ketchup.id, quantity: 1 } ])
      assert_equal 4_200, sale.total_cents, code
    end
    assert_equal 4, Review.where("reason LIKE ?", "The price rule failed%").count, "each different failure is reported"
  end

  test "a rule that would eat the memory is cut off and the built-in one decides" do
    Rule.create!(hook: "sale", user: users(:admin), code: "(define (d l n) (if (= n 0) (allow) (d (append l l) (- n 1)))) (d (list 1) 60)")
    sale = checkout([ { product_id: @ketchup.id, quantity: 1 } ])
    assert_match "append made something too big", Review.find_by!(reviewable: shifts(:store_open)).reason
    assert_equal 4_200, sale.total_cents
  end

  test "the same key never charges twice, even from another user or with another ticket" do
    first = Till.checkout!(branch: @store, user: @cashier, key: "same", lines: [ { product_id: @ketchup.id, quantity: 1 } ], payments: [ { payment_method: "cash", amount_cents: 4_200 } ])
    again = Till.checkout!(branch: @store, user: users(:supervisor), key: "same", lines: [ { product_id: @chicken.id, quantity: 2 } ], payments: [ { payment_method: "cash", amount_cents: 99_999 } ])
    assert_equal first, again
    assert_equal 1, Sale.count
    assert_equal BigDecimal("10"), StockLevel.quantity_for(@store, @chicken)
    assert_match "ticket", assert_raises(Till::Error) { Till.checkout!(branch: @store, user: @cashier, key: " ", lines: [], payments: []) }.message
  end

  test "if anything fails halfway nothing is left behind: no sale, no kardex, no folio spent" do
    last_folio = Folio.find_by(branch: @store, prefix: "sale")&.last.to_i
    assert_raises(Till::Error) { checkout([ { product_id: @ketchup.id, quantity: 2 }, { product_id: @chicken.id, quantity: 11 } ]) }
    assert_raises(Till::Error) { checkout([ { product_id: @ketchup.id, quantity: 2 } ], [ { payment_method: "voucher", amount_cents: 8_400 } ]) }
    assert_raises(ActiveRecord::RecordNotFound) { checkout([ { product_id: @ketchup.id, quantity: 2 }, { product_id: 0, quantity: 1 } ]) }
    assert_equal [ 0, 2 ], [ Sale.count, Movement.count ], "only the two inflows of the setup"
    assert_equal BigDecimal("5"), StockLevel.quantity_for(@store, @ketchup)
    assert_equal last_folio, Folio.find_by(branch: @store, prefix: "sale")&.last.to_i
  end

  test "payments: zero and negative ones are ignored, the change only comes out of cash" do
    sale = checkout([ { product_id: @ketchup.id, quantity: 1 } ],
                    [ { payment_method: "transfer", amount_cents: 4_000 }, { payment_method: "cash", amount_cents: 500 },
                      { payment_method: "deposit", amount_cents: 0 }, { payment_method: "cash", amount_cents: -900 } ])
    assert_equal 300, sale.change_cents
    assert_equal({ "transfer" => 4_000, "cash" => 500 }, sale.payments.pluck(:payment_method, :amount_cents).to_h)
    assert_equal 4_200, sale.paid_cents
    assert_equal 50_200, shifts(:store_open).expected_cash_cents
  end

  test "an inactive product is not sold even if the screen still has it" do
    @ketchup.update!(active: false)
    assert_raises(ActiveRecord::RecordNotFound) { checkout([ { product_id: @ketchup.id, quantity: 1 } ]) }
    assert_nil Scan.resolve(product_barcodes(:ketchup_ean).code), "its barcode no longer scans"
    assert_nil Scan.resolve(@ketchup.plu.to_s)
    assert_nil Scan.resolve(@ketchup.key)
  end
end
