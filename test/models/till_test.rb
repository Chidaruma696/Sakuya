require "test_helper"

class TillTest < ActiveSupport::TestCase
  setup do
    @store = branches(:store)
    @cashier = users(:cashier)
    @chicken = products(:chicken)
    @ketchup = products(:ketchup)
    Inventory.move!(branch: @store, product: @chicken, kind: "inflow", quantity: 10, user: @cashier)
    Inventory.move!(branch: @store, product: @ketchup, kind: "inflow", quantity: 5, user: @cashier)
    @weighed = { product_id: @chicken.id, quantity: "1.250" }
  end

  def checkout(lines, payments = nil, **extra)
    Till.checkout!(branch: @store, user: @cashier, lines: lines, key: SecureRandom.uuid,
                 payments: payments || [ { payment_method: "cash", amount_cents: 1_000_000 } ], **extra)
  end

  test "charges one product by the kilo and another by the piece, takes them out of stock and gives change" do
    sale = Till.checkout!(branch: @store, user: @cashier, key: "t1",
                         lines: [ @weighed, { product_id: @ketchup.id, quantity: 2 } ],
                         payments: [ { payment_method: "cash", amount_cents: 30_000 } ])
    # 1.250 × 129.00 = 161.25 ; 2 × 42.00 = 84.00 → 245.25
    assert_equal 24_525, sale.total_cents
    assert_equal 5_475, sale.change_cents
    assert_match(/\AB-\d{5}\z/, sale.folio)
    assert Barcode.valid?(sale.code)
    assert sale.code.start_with?("09")
    assert_equal BigDecimal("8.75"), StockLevel.quantity_for(@store, @chicken)
    assert_equal BigDecimal("3"), StockLevel.quantity_for(@store, @ketchup)
    assert_equal 2, Movement.where(reference: sale).count
    # the same key does not charge twice
    assert_equal sale, Till.checkout!(branch: @store, user: @cashier, key: "t1", lines: [ { product_id: @ketchup.id, quantity: 1 } ], payments: [])
  end

  test "a product without a price at the branch can be received but not sold" do
    @ketchup.update!(price_cents: 0)
    e = assert_raises(Till::Error) { checkout([ { product_id: @ketchup.id, quantity: 1 } ]) }
    assert_match "no price at Store 1", e.message
    @ketchup.set_price!(@store, "40")
    assert_equal 4_000, checkout([ { product_id: @ketchup.id, quantity: 1 } ]).total_cents
  end

  test "mixed payments: what is not cash cannot exceed the total and the change comes out of the cash" do
    sale = Till.checkout!(branch: @store, user: @cashier, key: "t2", lines: [ { product_id: @ketchup.id, quantity: 3 } ],
                         payments: [ { payment_method: "transfer", amount_cents: 10_000 }, { payment_method: "cash", amount_cents: 5_000 } ])
    assert_equal 12_600, sale.total_cents
    assert_equal 2_400, sale.change_cents
    assert_raises(Till::Error) do
      Till.checkout!(branch: @store, user: @cashier, key: "t3", lines: [ { product_id: @ketchup.id, quantity: 1 } ],
                   payments: [ { payment_method: "transfer", amount_cents: 10_000 } ])
    end
    assert_raises(Till::Error) do
      Till.checkout!(branch: @store, user: @cashier, key: "t4", lines: [ { product_id: @ketchup.id, quantity: 1 } ],
                   payments: [ { payment_method: "cash", amount_cents: 100 } ])
    end
  end

  test "does not sell without stock, without an open till, or fractions of a piece" do
    e = assert_raises(Till::Error) { checkout([ { product_id: @ketchup.id, quantity: 6 } ]) }
    assert_match "You cannot sell what is not there", e.message
    assert_raises(Till::Error) { checkout([ { product_id: @ketchup.id, quantity: "1.5" } ]) }
    shifts(:store_open).update!(status: "closed")
    e = assert_raises(Till::Error) { checkout([ { product_id: @ketchup.id, quantity: 1 } ]) }
    assert_match "no register open", e.message
    assert_equal 0, Sale.count
  end

  test "lowering the price: without permission it is stopped and reported; with permission it goes through in their name and goes to review; never below half" do
    line = { product_id: @ketchup.id, quantity: 1, price_cents: 3_000 }
    e = assert_raises(Till::Stopped) { checkout([ line ], [ { payment_method: "cash", amount_cents: 3_000 } ]) }
    assert_match "Ketchup 1 kg at $30.00 (should be $42.00)", e.message
    assert_equal 0, Sale.count
    report = Review.last
    assert report.stopped?
    assert_equal [ shifts(:store_open), @cashier, 1_200 ], [ report.reviewable, report.user, report.value_cents ]
    assert_raises(Till::Stopped) { checkout([ line ], [ { payment_method: "cash", amount_cents: 3_000 } ]) }
    assert_equal 1, Review.count, "the same attempt is not reported twice"
    sale = checkout([ line ], [ { payment_method: "cash", amount_cents: 3_000 } ], authorizer: users(:supervisor))
    assert_equal users(:supervisor), sale.lines.first.authorized_by
    assert_equal 4_200, sale.lines.first.catalog_cents
    assert_equal sale.lines.first, Review.last.reviewable, "with permission it is reported too"
    assert_not Review.last.stopped?
    assert_raises(Till::Error) { checkout([ { product_id: @ketchup.id, quantity: 1, price_cents: 2_000 } ], [ { payment_method: "cash", amount_cents: 2_000 } ], authorizer: users(:supervisor)) }
  end

  test "the shift balances: float + cash sales − refunds − withdrawals, and it blocks when the limit is exceeded" do
    shift = shifts(:store_open)
    sale = Till.checkout!(branch: @store, user: @cashier, key: "t5", lines: [ @weighed ],
                         payments: [ { payment_method: "cash", amount_cents: 20_000 } ])
    assert_equal 50_000 + 16_125, shift.expected_cash_cents
    shift.withdraw!(amount_cents: 10_000, reason: "to the safe", user: @cashier, authorized_by: users(:supervisor))
    assert_equal 56_125, shift.expected_cash_cents
    assert_raises(ArgumentError) { shift.withdraw!(amount_cents: 100_000, reason: "x", user: @cashier, authorized_by: users(:supervisor)) }

    refund = Till.refund!(sale: sale, lines: [ { sale_line_id: sale.lines.first.id, quantity: "1.250" } ], reason: "did not like it", user: @cashier)
    assert_equal 16_125, refund.total_cents
    assert_equal "refunded", sale.reload.status
    assert_equal BigDecimal("10"), StockLevel.quantity_for(@store, @chicken)
    assert_equal 40_000, shift.expected_cash_cents
    assert_raises(Till::Error) { Till.refund!(sale: sale, lines: [ { sale_line_id: sale.lines.first.id, quantity: 1 } ], reason: "again", user: @cashier) }

    @store.update!(cash_limit_cents: 45_000)
    Till.checkout!(branch: @store, user: @cashier, key: "t6", lines: [ { product_id: @ketchup.id, quantity: 2 } ], payments: [ { payment_method: "cash", amount_cents: 8_400 } ])
    e = assert_raises(Till::Error) { Till.checkout!(branch: @store, user: @cashier, key: "t7", lines: [ { product_id: @ketchup.id, quantity: 1 } ], payments: [ { payment_method: "cash", amount_cents: 4_200 } ]) }
    assert_match "drop cash into the safe", e.message

    shift.close!(counted_cents: 48_000, user: @cashier)
    assert_equal 48_400, shift.expected_cents
    assert_equal(-400, shift.difference_cents)
    new = Shift.open!(branch: @store, user: @cashier, float_cents: 30_000)
    assert_raises(ArgumentError) { Shift.open!(branch: @store, user: @cashier, float_cents: 1) }
    assert_equal 30_000, new.expected_cash_cents
  end

  test "a partial refund leaves the sale paid and respects what is still pending" do
    sale = Till.checkout!(branch: @store, user: @cashier, key: "t8", lines: [ { product_id: @ketchup.id, quantity: 3 } ], payments: [ { payment_method: "cash", amount_cents: 12_600 } ])
    line = sale.lines.first
    Till.refund!(sale: sale, lines: [ { sale_line_id: line.id, quantity: 1 } ], reason: "dented", user: @cashier)
    assert sale.reload.paid?
    assert_equal BigDecimal("2"), line.pending_quantity
    assert_raises(Till::Error) { Till.refund!(sale: sale, lines: [ { sale_line_id: line.id, quantity: 3 } ], reason: "x", user: @cashier) }
    assert_equal Sale.search(sale.code), sale
    assert_equal Sale.search(" #{sale.folio.downcase} "), sale
  end

  test "the branch price overrides the general one, and the floor is measured against it" do
    @ketchup.set_price!(@store, "50.00")
    sale = checkout([ { product_id: @ketchup.id, quantity: 1 } ])
    assert_equal 5_000, sale.lines.first.catalog_cents
    assert_equal 4_200, @ketchup.price_cents_for(branches(:head_office))
    @ketchup.set_price!(@store, "")
    assert_equal 4_200, @ketchup.reload.price_cents_for(@store)
  end

  test "the till applies the promotion by itself, marks it on the line and a discount is measured against it" do
    Inventory.move!(branch: @store, product: @ketchup, kind: "inflow", quantity: 20, user: @cashier)
    promo = Promotion.create!(name: "Wholesale", product: @ketchup, kind: "by_quantity", minimum_quantity: 3, price_cents: 3_500)
    sale = checkout([ { product_id: @ketchup.id, quantity: 3 } ])
    line = sale.lines.first
    assert_equal 3_500, line.price_cents
    assert_equal 4_200, line.catalog_cents
    assert_equal promo, line.promotion
    assert_equal 10_500, sale.total_cents
    without = checkout([ { product_id: @ketchup.id, quantity: 2 } ])
    assert_nil without.lines.first.promotion
    assert_equal 4_200, without.lines.first.price_cents
    assert_raises(Till::Stopped, "below the promotion is also lowering the price") { checkout([ { product_id: @ketchup.id, quantity: 3, price_cents: 3_400 } ]) }
    with = checkout([ { product_id: @ketchup.id, quantity: 3, price_cents: 3_400 } ], nil, authorizer: users(:supervisor))
    assert_nil with.lines.first.promotion
    assert_equal users(:supervisor), with.lines.first.authorized_by
  end

  test "a custom price rule: small discounts go through, medium ones are reviewed and ketchup is never discounted" do
    Rule.create!(hook: "price", user: users(:admin), code: <<~LISP)
      (cond ((= (discount) 0) (allow))
            ((= (product) "KETC") (reject "ketchup is never discounted"))
            ((<= (discount) 5) (allow))
            (else (to-review "medium discount")))
    LISP
    per_kg = @chicken.price_cents_for(@store)
    sale = checkout([ { product_id: @chicken.id, quantity: 1, price_cents: (per_kg * 0.96).round } ])
    assert_equal 0, Review.count, "4 % just goes through"
    sale = checkout([ { product_id: @chicken.id, quantity: 1, price_cents: (per_kg * 0.9).round } ])
    assert_equal [ sale.lines.first, "medium discount" ], [ Review.last.reviewable, Review.last.reason.split(": ").last ]
    assert_match "ketchup is never discounted", assert_raises(Till::Stopped) { checkout([ { product_id: @ketchup.id, quantity: 1, price_cents: 4_100 } ]) }.message
    Rule.create!(hook: "price", user: users(:admin), code: "(not-found)")
    2.times { checkout([ @weighed ]) }
    assert_equal 1, Review.where("reason LIKE ?", "The price rule failed%").count, "the failure is reported once per shift"
  end

  test "a custom sales rule: stops by product, sends large ones to review and the supervisor forces it through" do
    Rule.create!(hook: "sale", user: users(:admin), code: <<~LISP)
      (cond ((> (quantity-of "ketc") 1) (reject "ketchup one at a time"))
            ((> (total) 100) (to-review "large sale"))
            ((> (paid-with :transfer) 0) (to-review "transfer"))
            (else (allow)))
    LISP
    assert_equal 0, checkout([ { product_id: @ketchup.id, quantity: 1 } ]).then { Review.count }
    e = assert_raises(Till::Stopped) { checkout([ { product_id: @ketchup.id, quantity: 2 } ]) }
    assert_match "ketchup one at a time. It cannot be charged like this", e.message
    assert_equal [ shifts(:store_open), 8_400, true ], [ Review.last.reviewable, Review.last.value_cents, Review.last.stopped ]
    sale = checkout([ @weighed ])
    assert_equal [ sale, "large sale" ], [ Review.last.reviewable, Review.last.reason ]
    assert_match "Sale #{sale.folio} of $161.25", Review.last.description
    checkout([ { product_id: @ketchup.id, quantity: 1 } ], [ { payment_method: "transfer", amount_cents: 4_200 } ])
    assert_equal "transfer", Review.last.reason
    forced = Till.checkout!(branch: @store, user: users(:supervisor), key: "f", lines: [ { product_id: @ketchup.id, quantity: 2 } ],
                           payments: [ { payment_method: "cash", amount_cents: 8_400 } ])
    assert_equal [ forced, "ketchup one at a time" ], [ Review.last.reviewable, Review.last.reason ], "with till.force_sale it is charged and goes to review"
  end

  test "money: formatting and rounding" do
    assert_equal "$1,234.50", Money.format_money(123_450)
    assert_equal "−$0.05", Money.format_money(-5)
    assert_equal 12_900, Money.cents("129.00")
    assert_equal 16_125, Money.amount("1.250", 12_900)
    assert_equal 4_302, Money.amount("0.3335", 12_900)
  end
end
