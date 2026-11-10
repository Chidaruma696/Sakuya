require "test_helper"

# The books always add up. A long run of made-up tickets, refunds and withdrawals (the same ones
# every time: the dice are seeded) and, after each step, the identities that must hold no matter
# what was sold.
class TillAccountingTest < ActiveSupport::TestCase
  STEPS = 60

  setup do
    @store = branches(:store)
    @store.update!(cash_limit_cents: 100_000_000)
    @cashier = users(:supervisor) # may lower prices and withdraw: more paths get exercised
    @shift = shifts(:store_open)
    @dice = Random.new(2026_11_10)
    @products = [ products(:chicken), products(:ketchup),
                  Product.create!(key: "RICE", name: "Rice", unit: "kg", price_cents: 1_990),
                  Product.create!(key: "SODA", name: "Soda", unit: "piece", price_cents: 1_850),
                  Product.create!(key: "ROPE", name: "Rope", unit: "meter", price_cents: 333) ]
    @received = @products.to_h { |p| [ p, 500 ] }
    @received.each { |p, quantity| Inventory.move!(branch: @store, product: p, kind: "inflow", quantity: quantity, user: @cashier) }
    Promotion.create!(name: "A third off", product: products(:ketchup), kind: "percentage", percentage: 33)
    Promotion.create!(name: "By the sack", product: @products[2], kind: "by_quantity", minimum_quantity: 5, price_cents: 1_750)
  end

  def quantity_for(product)
    product.fractional? ? BigDecimal(@dice.rand(1..9_999)) / 1000 : @dice.rand(1..6)
  end

  def random_ticket
    lines = Array.new(@dice.rand(1..5)) do
      product = @products.sample(random: @dice)
      line = { product_id: product.id, quantity: quantity_for(product).to_s }
      line[:price_cents] = (product.price_cents * @dice.rand(60..99) / 100.0).ceil if @dice.rand(6).zero?
      line
    end
    paid = [ { payment_method: "cash", amount_cents: 10_000_000 } ]
    paid.unshift({ payment_method: %w[transfer deposit].sample(random: @dice), amount_cents: @dice.rand(1..300) }) if @dice.rand(3).zero?
    Till.checkout!(branch: @store, user: @cashier, authorizer: @cashier, key: SecureRandom.uuid, lines: lines, payments: paid)
  end

  def random_refund
    sale = Sale.where(status: "paid").order(:id).to_a.sample(random: @dice) or return
    line = sale.lines.select { |l| l.pending_quantity.positive? }.sample(random: @dice)
    quantity = line.product.fractional? ? [ quantity_for(line.product), line.pending_quantity ].min : @dice.rand(1..line.pending_quantity.to_i)
    Till.refund!(sale: sale, lines: [ { sale_line_id: line.id, quantity: quantity.to_s } ], reason: "seeded", user: @cashier)
  end

  def random_withdrawal
    amount = @dice.rand(1..[ @shift.expected_cash_cents, 1 ].max)
    @shift.withdraw!(amount_cents: amount, reason: "to the safe", user: @cashier) if amount <= @shift.expected_cash_cents
  end

  def assert_books_add_up(step)
    Sale.includes(:lines, :payments, :refunds).find_each do |sale|
      assert_equal sale.total_cents, sale.lines.sum(&:amount_cents), "#{step}: a sale is the sum of its lines"
      assert_equal sale.total_cents, sale.payments.sum(&:amount_cents) - sale.change_cents, "#{step}: what was paid minus the change is the total"
      assert_operator sale.change_cents, :<=, sale.payments.select { |p| p.payment_method == "cash" }.sum(&:amount_cents), "#{step}: change only comes out of cash"
      assert_operator sale.total_refunded_cents, :<=, sale.total_cents, "#{step}: never more refunded than charged"
      sale.lines.each do |line|
        assert_equal Money.amount(line.quantity, line.price_cents), line.amount_cents
        assert_operator line.refund_lines.sum(:amount_cents), :<=, line.amount_cents, "#{step}: a line never gives back more than it took"
        assert_operator line.pending_quantity, :>=, 0
        assert_equal line.amount_cents, line.refund_lines.sum(:amount_cents), "#{step}: a line returned whole gives back exactly what it took" if line.pending_quantity.zero?
      end
      assert_equal sale.lines.all? { |l| l.pending_quantity.zero? }, sale.status == "refunded", "#{step}: refunded means everything came back"
    end

    cash_in = Payment.where(payment_method: "cash").sum(:amount_cents) - Sale.sum(:change_cents)
    assert_equal 50_000 + cash_in - Refund.sum(:total_cents) - Withdrawal.sum(:amount_cents), @shift.expected_cash_cents, "#{step}: the drawer"
    assert_operator @shift.expected_cash_cents, :>=, 0, "#{step}: withdrawals never take more than there is"

    @products.each do |product|
      sold = SaleLine.where(product: product).sum(:quantity)
      back = RefundLine.joins(:sale_line).where(sale_lines: { product_id: product.id }).sum(:quantity)
      level = StockLevel.quantity_for(@store, product)
      assert_equal @received[product] - sold + back, level, "#{step}: stock of #{product.key}"
      last = Movement.where(branch: @store, product: product).order(:id).last
      assert_equal level, last.balance, "#{step}: the kardex ends on the stock level"
      replayed = Movement.where(branch: @store, product: product).order(:id).sum { |m| Movement.sign(m.kind) * m.quantity }
      assert_equal level, replayed, "#{step}: replaying the kardex gives the stock level"
    end

    folios = Sale.pluck(:folio)
    assert_equal folios.size, folios.uniq.size, "#{step}: no folio twice"
    assert_equal (1..folios.size).map { |n| format("B-%05d", n) }, folios.sort, "#{step}: no folio skipped"
  end

  test "sixty seeded steps of selling, refunding and withdrawing: every identity holds after each one" do
    STEPS.times do |step|
      case @dice.rand(10)
      when 0..5 then random_ticket
      when 6..8 then random_refund
      else random_withdrawal
      end
      assert_books_add_up(step) if (step % 6).zero? || step == STEPS - 1
    end
    assert_operator Sale.count, :>, 20, "the run actually sold"
    assert_operator Refund.count, :>, 5, "and refunded"

    counted = @shift.expected_cash_cents - 137
    @shift.close!(counted_cents: counted, user: @cashier)
    assert_equal [ counted, -137 ], [ @shift.counted_cents, @shift.difference_cents ]
    assert_equal @shift.expected_cents, @shift.expected_cash_cents, "closing freezes what was expected"
  end
end
