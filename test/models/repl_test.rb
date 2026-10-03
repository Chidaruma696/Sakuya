require "test_helper"

class ReplTest < ActiveSupport::TestCase
  setup do
    @store = branches(:store)
    Inventory.move!(branch: @store, product: products(:ketchup), kind: "inflow", quantity: 10, user: users(:admin))
    Inventory.move!(branch: @store, product: products(:chicken), kind: "inflow", quantity: 5, user: users(:admin))
    checkout = ->(key, lines, user) {
      Till.checkout!(branch: @store, user: user, key: key, lines: lines, payments: [ { payment_method: "cash", amount_cents: 1_000_000 } ])
    }
    checkout.("a", [ { product_id: products(:ketchup).id, quantity: 2 } ], users(:cashier))
    checkout.("b", [ { product_id: products(:chicken).id, quantity: "1.5" } ], users(:cashier))
    checkout.("c", [ { product_id: products(:ketchup).id, quantity: 1 } ], users(:supervisor))
  end

  def ev(text, branches: [ @store ]) = Repl.evaluate(text, branches: branches)

  test "today's sales as a list of maps, and the tools to add them up, count them and sort them" do
    sales = ev("(sales)")
    assert_equal 3, sales.size
    assert_equal %i[folio date branch cashier customer total change status], sales.first.keys
    assert_equal BigDecimal("319.50"), ev("(sum-of :total (sales))"), "84 + 193.50 + 42"
    assert_equal({ "Cashier" => 2, "Supervisor" => 1 }, ev("(count-by :cashier (sales))"))
    assert_equal BigDecimal("193.50"), ev("(get (first (sort-by-desc :total (sales))) :total)")
    assert_equal [ "KETC", "KETC" ], ev('(pluck :code (where :code "KETC" (sale-lines)))')
    assert_equal 0, ev("(count (sales (days-ago 30) (days-ago 1)))")
    assert_equal BigDecimal("7"), ev('(get (first (stock "ketc")) :quantity)')
  end

  test "only sees the branches it is allowed to" do
    assert_equal 0, ev("(count (sales))", branches: [ branches(:head_office) ])
    assert_equal 3, ev("(count (sales))", branches: Branch.all)
  end

  test "does not write even if it tries, and explains what it does not understand" do
    assert_match "only reads", assert_raises(Lisp::Error) { Repl.read_only { products(:ketchup).update!(name: "x") } }.message
    assert_equal "Ketchup 1 kg", products(:ketchup).reload.name
    assert_match "I do not understand the date", assert_raises(Lisp::Error) { ev('(sales "yesterday")') }.message
    assert_match "expected a map", assert_raises(Lisp::Error) { ev("(sum-of :total (list 1 2))") }.message
    assert_raises(Lisp::Exhausted) { ev("(define (f n) (f n)) (f 1)") }
  end
end
