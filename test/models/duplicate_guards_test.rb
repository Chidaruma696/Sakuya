require "test_helper"

# What the database itself refuses when two requests get past the checks at the same instant, and
# the other guards around numbering, whole pieces, plugins and the rules file.
class DuplicateGuardsTest < ActiveSupport::TestCase
  setup do
    @store = branches(:store)
    @head_office = branches(:head_office)
    @admin = users(:admin)
    @ketchup = products(:ketchup)
    @chicken = products(:chicken)
  end

  # Runs the block as if the check that normally stops a duplicate had seen nothing yet.
  def blind(target, method, result)
    original = target.method(method)
    target.define_singleton_method(method) { |*, **| result }
    yield
  ensure
    target.define_singleton_method(method, original)
  end

  test "the database allows one open shift per branch, however the second one gets there" do
    assert_raises(ActiveRecord::RecordNotUnique) { Shift.create!(branch: @store, user: @admin, float_cents: 0, opened_at: Time.current) }
    blind(Shift, :opened_at, nil) do
      error = assert_raises(ArgumentError) { Shift.open!(branch: @store, user: @admin, float_cents: 0) }
      assert_match "already an open register session at Store 1", error.message
    end
    assert_equal 1, Shift.still_open.where(branch: @store).count
    shifts(:store_open).close!(counted_cents: 50_000, user: @admin)
    assert Shift.open!(branch: @store, user: @admin, float_cents: 0).open?, "closed shifts do not count"
    assert Shift.open!(branch: @head_office, user: @admin, float_cents: 0).open?, "nor do other branches"
  end

  test "the database allows one open stock count per branch" do
    count = StockCount.open!(branch: @store, user: @admin, responsible: @admin)
    assert_raises(ActiveRecord::RecordNotUnique) { StockCount.create!(branch: @store, user: @admin, responsible: @admin) }
    blind(StockCount, :still_open, StockCount.none) do
      error = assert_raises(ArgumentError) { StockCount.open!(branch: @store, user: @admin, responsible: @admin) }
      assert_match "already an open count at Store 1", error.message
    end
    assert_equal 1, StockCount.where(branch: @store, status: "open").count
    count.close!(user: @admin)
    assert StockCount.open!(branch: @store, user: @admin, responsible: @admin).open?
  end

  test "the same key never leaves two withdrawals, payments or refunds, even past the first check" do
    shift = shifts(:store_open)
    first = shift.withdraw!(amount_cents: 1_000, reason: "x", user: @admin, key: "k")
    assert_equal first, shift.withdraw!(amount_cents: 9_999, reason: "y", user: @admin, key: "k")
    blind(Withdrawal, :find_by, nil) do
      assert_raises(ActiveRecord::RecordNotUnique) { shift.withdraw!(amount_cents: 1_000, reason: "x", user: @admin, key: "k") }
    end
    assert_equal 2, [ shift.withdraw!(amount_cents: 1, reason: "x", user: @admin), shift.withdraw!(amount_cents: 1, reason: "x", user: @admin) ].uniq.size, "without a key each one counts"

    customer = Customer.create!(name: "Ana")
    pay = -> { AccountPayment.register!(customer: customer, branch: @store, user: @admin, amount_cents: 500, payment_method: "cash", key: "a") }
    assert_equal pay.call, pay.call
    blind(AccountPayment, :find_by, nil) { assert_raises(ActiveRecord::RecordNotUnique) { pay.call } }
    assert_equal [ 1, -500 ], [ AccountPayment.count, customer.balance_cents ], "the refused one left nothing behind, not even its account line"

    supplier = Supplier.create!(name: "S")
    Purchases.invoice!(supplier: supplier, branch: @store, user: @admin, folio: "F-1", date: Date.current, amount_cents: 10_000)
    settle = -> { Purchases.pay!(supplier: supplier, branch: @store, user: @admin, amount_cents: 2_000, payment_method: "transfer", key: "s") }
    assert_equal settle.call, settle.call
    blind(SupplierPayment, :find_by, nil) { assert_raises(ActiveRecord::RecordNotUnique) { settle.call } }
    assert_equal [ 1, 8_000 ], [ SupplierPayment.count, supplier.reload.balance_cents ]
  end

  test "folios are never handed out twice when the numbering mode or a prefix changes" do
    Inventory.move!(branch: @store, product: @ketchup, kind: "inflow", quantity: 20, user: @admin)
    sell = -> { Till.checkout!(branch: @store, user: @admin, key: SecureRandom.uuid, lines: [ { product_id: @ketchup.id, quantity: 1 } ], payments: [ { payment_method: "cash", amount_cents: 4_200 } ]).folio }
    assert_equal %w[B-00001 B-00002 B-00003], 3.times.map { sell.call }
    Setting.store!("folios.mode" => "single", "folios.single" => "B") # one sequence for everything, starting over, same letter
    assert_equal "B-00004", sell.call, "the numbers the sales already used are skipped"
    Setting.store!("folios.mode" => "per_document")
    assert_equal "B-00005", sell.call, "and going back does not reuse the one taken meanwhile"
    Setting.store!("folios.sale" => "C") # the shifts' own letter
    assert_equal "C-00006", sell.call, "another document's letter is fine: each keeps its own table"
    assert_equal Sale.count, Sale.distinct.count(:folio)
  end

  test "what is sold by the piece moves in whole pieces everywhere, not just at the till" do
    supplier = Supplier.create!(name: "S")
    assert_match "whole pieces", assert_raises(ActiveRecord::RecordInvalid) {
      Purchases.receive!(branch: @store, supplier: supplier, user: @admin, lines: [ { product_id: @ketchup.id, quantity: "2.5" } ])
    }.message
    assert_equal [ 0, 0 ], [ Receipt.count, StockLevel.quantity_for(@store, @ketchup) ]
    Purchases.receive!(branch: @store, supplier: supplier, user: @admin, lines: [ { product_id: @ketchup.id, quantity: "3" }, { product_id: @chicken.id, quantity: "2.5" } ])
    assert_match "whole pieces", assert_raises(ActiveRecord::RecordInvalid) {
      StockTransfer.register!(origin: @store, destination: @head_office, user: @admin, lines: [ { product_id: @ketchup.id, quantity: "1.5" } ])
    }.message
    assert_equal [ 0, 3 ], [ StockTransfer.count, StockLevel.quantity_for(@store, @ketchup) ]
    StockTransfer.register!(origin: @store, destination: @head_office, user: @admin, lines: [ { product_id: @chicken.id, quantity: "1.5" } ])
    count = StockCount.open!(branch: @store, user: @admin, responsible: @admin)
    assert_match "whole pieces", assert_raises(ArgumentError) { count.count_manual!(@ketchup, "2.5") }.message
    count.count_manual!(@ketchup, "2")
    count.count_manual!(@chicken, "0.75")
  end

  test "a plugin definition that breaks takes only itself out: the rules that do not use it keep deciding" do
    plugin = Plugin.install!(<<~LISP, user: @admin)
      (plugin "fonda" (name "Fonda"))
      (define fonda/broken (no-such-function))
      (define fonda/endless ((lambda (f) (f f)) (lambda (f) (f f))))
      (define (fonda/double x) (* x 2))
    LISP
    plugin.update!(active: true)
    data = PriceRule::Input.new(product: @ketchup, quantity: 1, price: 4_200, catalog: 4_200, regular: 4_200, authorized: false)
    decision = PriceRule.decide(data, code: %((if (= (fonda/double 21) 42) (to-review "plugin alive") (reject "plugin dead"))))
    assert_equal [ :review, "plugin alive", nil ], [ decision.verdict, decision.reason, decision.error ]
    uses_broken = PriceRule.decide(data, code: "(if fonda/broken (allow) (allow))")
    assert_equal :allow, uses_broken.verdict, "the built-in rule decided"
    assert_match "I don’t know “fonda/broken”", uses_broken.error
    assert_equal 42, Repl.evaluate("(fonda/double 21)", branches: [ @store ])
  end

  test "the rules file refuses a contract newer than this installation knows; older ones come in" do
    newer = ";;; hook: shift (contract #{ShiftRule::VERSION + 1})\n(allow)\n"
    error = assert_raises(Lisp::Error) { RulesFile.import!(newer, user: @admin) }
    assert_match "says contract #{ShiftRule::VERSION + 1}, and this Sakuya knows up to #{ShiftRule::VERSION}", error.message
    assert_equal 0, Rule.count
    assert_equal %w[credit], RulesFile.import!(";;; hook: credit (contract 1)\n(reject :no-credit)\n", user: @admin)
    assert Rule.current("credit").old?
  end
end
