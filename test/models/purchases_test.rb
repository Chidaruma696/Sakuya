require "test_helper"

# Purchases: a receipt that goes into inventory, an invoice that creates the debt (the price
# only lives there), a payment that leaves the drawer and is credited in the same transaction, a void
# that compensates, cancellations with their locks, and the invoiced-versus-received comparison.
class PurchasesTest < ActiveSupport::TestCase
  setup do
    @head_office = branches(:head_office)
    @admin = users(:admin)
    @chicken = products(:chicken)
    @ketchup = products(:ketchup)
    @supplier = Supplier.create!(name: "Valley Poultry", credit_days: 15)
  end

  def receive(lines = [ { product_id: @chicken.id, quantity: "20", boxes: 2 } ], **extra)
    Purchases.receive!(branch: @head_office, supplier: @supplier, user: @admin, lines: lines, **extra)
  end

  test "receiving goes into inventory, gets an RC folio per branch and is idempotent by key" do
    r = receive(delivery_note: "R-77", key: "abc")
    assert_match(/\ARC-/, r.folio)
    assert_equal 20, StockLevel.quantity_for(@head_office, @chicken)
    assert_equal r, receive(key: "abc"), "the same key returns the same receipt"
    assert_equal 20, StockLevel.quantity_for(@head_office, @chicken)
    assert_raises(Purchases::Error) { receive([]) }
  end

  test "cancelling the receipt takes the goods out and releases the invoice" do
    f = Purchases.invoice!(supplier: @supplier, branch: @head_office, user: @admin, folio: "A-1", date: Date.current, amount_cents: 100_00)
    r = receive(invoice: f)
    Purchases.cancel_receipt!(r, reason: "entered twice", user: @admin)
    assert r.reload.cancelled?
    assert_nil r.invoice
    assert_equal 0, StockLevel.quantity_for(@head_office, @chicken)
    assert_raises(Purchases::Error) { Purchases.cancel_receipt!(r, reason: "once more", user: @admin) }
  end

  test "the invoice creates the debt: with lines the amount is derived, it falls due after the credit days and the folio cannot repeat" do
    f = Purchases.invoice!(supplier: @supplier, branch: @head_office, user: @admin, folio: "F-100", date: Date.new(2026, 9, 1),
                          lines: [ { product_id: @chicken.id, quantity: "10", price: "95.50" }, { product_id: @ketchup.id, quantity: "3", price: "30" } ])
    assert_equal 955_00 + 90_00, f.amount_cents
    assert_equal Date.new(2026, 9, 16), f.due
    assert_equal f.amount_cents, @supplier.balance_cents
    assert_equal 0, StockLevel.quantity_for(@head_office, @chicken), "invoicing does not touch inventory"
    assert_raises(Purchases::Error) { Purchases.invoice!(supplier: @supplier, branch: @head_office, user: @admin, folio: "F-100", date: Date.current, amount_cents: 1) }
    assert_raises(Purchases::Error) { Purchases.invoice!(supplier: @supplier, branch: @head_office, user: @admin, folio: "F-101", date: Date.current, amount_cents: 0) }
  end

  test "a cash payment leaves the drawer as a withdrawal and is credited; without an open till there is no cash payment" do
    f = Purchases.invoice!(supplier: @supplier, branch: @head_office, user: @admin, folio: "F-1", date: Date.current, amount_cents: 500_00)
    assert_raises(Purchases::Error) { Purchases.pay!(supplier: @supplier, branch: @head_office, user: @admin, amount_cents: 100_00, invoice: f) }
    shift = Shift.open!(branch: @head_office, user: @admin, float_cents: 1_000_00)
    payment = Purchases.pay!(supplier: @supplier, branch: @head_office, user: @admin, amount_cents: 300_00, invoice: f)
    assert_equal 300_00, payment.withdrawal.amount_cents
    assert_equal 700_00, shift.reload.expected_cash_cents
    assert_equal 200_00, f.reload.remaining_cents
    assert_equal 200_00, @supplier.balance_cents
    assert_raises(Purchases::Error, "cannot exceed what remains") { Purchases.pay!(supplier: @supplier, branch: @head_office, user: @admin, amount_cents: 200_01, invoice: f) }
    assert_raises(Purchases::Error, "more than what is owed without an invoice") { Purchases.pay!(supplier: @supplier, branch: @head_office, user: @admin, amount_cents: 200_01) }
    transfer = Purchases.pay!(supplier: @supplier, branch: @head_office, user: @admin, amount_cents: 200_00, payment_method: "transfer", invoice: f)
    assert_nil transfer.withdrawal
    assert_equal 700_00, shift.reload.expected_cash_cents, "the transfer does not touch the till"
    assert f.reload.paid?
    assert_equal 0, @supplier.balance_cents
  end

  test "voiding a payment compensates the credit and returns the cash only while the shift is open" do
    f = Purchases.invoice!(supplier: @supplier, branch: @head_office, user: @admin, folio: "F-2", date: Date.current, amount_cents: 500_00)
    shift = Shift.open!(branch: @head_office, user: @admin, float_cents: 1_000_00)
    payment = Purchases.pay!(supplier: @supplier, branch: @head_office, user: @admin, amount_cents: 300_00, invoice: f)
    Purchases.void_payment!(payment, reason: "paid twice", user: @admin)
    assert_equal "voided", payment.reload.status
    assert_equal 1_000_00, shift.reload.expected_cash_cents
    assert_equal 500_00, @supplier.balance_cents
    assert_equal 500_00, f.reload.remaining_cents
    assert_equal %w[charge payment adjustment], @supplier.movements.order(:id).pluck(:kind)

    other = Purchases.pay!(supplier: @supplier, branch: @head_office, user: @admin, amount_cents: 100_00, invoice: f)
    shift.close!(counted_cents: shift.reload.expected_cash_cents, user: @admin)
    assert_raises(Purchases::Error) { Purchases.void_payment!(other, reason: "late", user: @admin) }
    assert other.reload.current?
  end

  test "cancelling the invoice reverses the debt, releases receipts and is refused while payments stand" do
    f = Purchases.invoice!(supplier: @supplier, branch: @head_office, user: @admin, folio: "F-3", date: Date.current, amount_cents: 400_00)
    r = receive(invoice: f)
    Purchases.invoice!(supplier: @supplier, branch: @head_office, user: @admin, folio: "F-4", date: Date.current, amount_cents: 50_00)
    shift = Shift.open!(branch: @head_office, user: @admin, float_cents: 1_000_00)
    payment = Purchases.pay!(supplier: @supplier, branch: @head_office, user: @admin, amount_cents: 100_00, invoice: f)
    assert_raises(Purchases::Error) { Purchases.cancel_invoice!(f, reason: "entered wrong", user: @admin) }
    Purchases.void_payment!(payment, reason: "to cancel", user: @admin)
    Purchases.cancel_invoice!(f, reason: "entered wrong", user: @admin)
    assert f.reload.cancelled?
    assert_nil r.reload.invoice
    assert r.registered?, "the goods stay"
    assert_equal 50_00, @supplier.balance_cents
    assert_equal 1_000_00, shift.reload.expected_cash_cents
  end

  test "the comparison tells what is missing and what is extra between what was invoiced and what was received" do
    f = Purchases.invoice!(supplier: @supplier, branch: @head_office, user: @admin, folio: "F-5", date: Date.current,
                          lines: [ { product_id: @chicken.id, quantity: "20", price: "90" }, { product_id: @ketchup.id, quantity: "5", price: "30" } ])
    receive([ { product_id: @chicken.id, quantity: "18" } ], invoice: f)
    receive([ { product_id: @chicken.id, quantity: "2" } ], invoice: f)
    other = Product.create!(key: "ICE", name: "Ice", line: "Supplies", unit: "piece", price_cents: 100)
    receive([ { product_id: other.id, quantity: "1" } ], invoice: f)
    statuses = Purchases.comparison(f).to_h { |c| [ c.product.key, c.status ] }
    assert_equal({ "CHKN" => "matches", "ICE" => "no_invoice", "KETC" => "not_received" }, statuses)
  end

  test "the ledgers cannot be edited or deleted" do
    Purchases.invoice!(supplier: @supplier, branch: @head_office, user: @admin, folio: "F-6", date: Date.current, amount_cents: 10_00)
    assert_raises(ActiveRecord::ReadOnlyRecord) { @supplier.movements.first.destroy! }
    assert_raises(ActiveRecord::RecordNotDestroyed) { @supplier.destroy! }
  end
end
