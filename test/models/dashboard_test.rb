require "test_helper"

class DashboardTest < ActiveSupport::TestCase
  setup do
    @store = branches(:store)
    Inventory.move!(branch: @store, product: products(:ketchup), kind: "inflow", quantity: 10, user: users(:admin))
    Till.checkout!(branch: @store, user: users(:cashier), key: "t1", lines: [ { product_id: products(:ketchup).id, quantity: 3 } ],
                 payments: [ { payment_method: "cash", amount_cents: 20_000 } ])
    @data = Dashboard::Input.new(branches: [ @store ], from: Date.current, to: Date.current)
  end

  def pieces(code) = Dashboard.evaluate(code, @data)

  test "the built-in one brings the usual eight figures and the three lists" do
    p = pieces(Dashboard::DEFAULT)
    assert_equal 8, p.count { |x| x.kind == :tile }
    assert_equal %i[top-products closed-cash-counts stock-counts], p.select { |x| x.kind == :panel }.map(&:panel)
    sales = p.first
    assert_equal "Ventas", I18n.with_locale(:es) { pieces("(dashboard (tile :sales))").first.title }
    assert_equal BigDecimal("126"), sales.value
    assert_equal :money, sales.format
  end

  test "custom, conditional and per-product figures" do
    p = pieces(<<~LISP)
      (define margin (- (sales) (returns)))
      (dashboard
        (tile "Margin" margin :money)
        (tile "Ketchup sold" (sold "ketc"))
        (when (> (returns) 0) (tile :returns))
        (map (fn (d) (tile (str "Day " d) d)) '(1 2))
        (panel :top-products 3))
    LISP
    assert_equal [ "Margin", "Ketchup sold", "Day 1", "Day 2", nil ], p.map(&:title)
    assert_equal BigDecimal("126"), p[0].value
    assert_equal BigDecimal("3"), p[1].value
    assert_equal 3, p.last.limit
  end

  test "what does not fit is explained in words" do
    assert_match "(dashboard", assert_raises(Lisp::Error) { pieces("(tile :sales)") }.message
    assert_match "there is no figure :profit", assert_raises(Lisp::Error) { pieces("(dashboard (tile :profit))") }.message
    assert_match "there is no list :wastes", assert_raises(Lisp::Error) { pieces("(dashboard (panel :wastes))") }.message
    assert_match "there is no product with code NOTHING", assert_raises(Lisp::Error) { pieces(%((dashboard (tile "x" (sold "nothing"))))) }.message
    assert_match "the format is one of", assert_raises(Lisp::Error) { pieces(%((dashboard (tile "x" 1 :currency)))) }.message
    assert_raises(Lisp::Error) { pieces("(dashboard 42)") }
  end

  test "if the saved program blows up, the built-in one shows with the reason why" do
    p, error = Dashboard.build(@data, code: "(dashboard (tile :nothing))")
    assert_match "there is no figure", error
    assert_equal 8, p.count { |x| x.kind == :tile }
    p, error = Dashboard.build(@data, code: "(dashboard (tile :tickets))")
    assert_nil error
    assert_equal [ 1 ], p.map(&:value)
  end

  test "rules cannot be edited or deleted; the current one is the latest" do
    r = Rule.create!(hook: "dashboard", code: "(dashboard)", user: users(:admin))
    Rule.create!(hook: "dashboard", code: "(dashboard (tile :sales))", user: users(:admin))
    assert_equal "(dashboard (tile :sales))", Rule.current("dashboard").code
    assert_raises(ActiveRecord::ReadOnlyRecord) { r.update!(code: "x") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { r.destroy! }
    assert_not Rule.new(hook: "other", code: "1", user: users(:admin)).valid?
  end
end
