require "test_helper"

class StockCountsDashboardTest < ActionDispatch::IntegrationTest
  setup do
    @store = branches(:store)
    post login_path, params: { user: "supervisor", password: "secret12" }
    Inventory.move!(branch: @store, product: products(:ketchup), kind: "inflow", quantity: 5, user: users(:supervisor))
    Inventory.move!(branch: @store, product: products(:chicken), kind: "inflow", quantity: "1.5", user: users(:supervisor))
  end

  test "counting on screen: open, scan, type in, close and see the charge" do
    post stock_counts_path, params: { responsible_id: users(:cashier).id }
    stock_count = StockCount.last
    assert_redirected_to stock_count_path(stock_count)
    4.times { post scan_stock_count_path(stock_count), params: { code: "KETC" } }
    assert_match "one more piece", flash[:notice]
    post scan_stock_count_path(stock_count), params: { code: "CHKN" }
    assert_match "type it in by hand", flash[:alert]
    post manual_stock_count_path(stock_count), params: { product_id: products(:chicken).id, quantity: "1.5" }
    get stock_count_path(stock_count)
    assert_select "td", /Ketchup/
    post close_stock_count_path(stock_count)
    assert_equal 4_200, stock_count.reload.shortage_cents
    get charges_path
    assert_select "td", /Cashier/
    post resolve_charge_path(Charge.last, status: "paid")
    assert_equal "paid", Charge.last.reload.status
    get stock_counts_path
    assert_select "td", /#{stock_count.folio}/
  end

  test "partial count by line from the screen, and the warning that a count is due" do
    get new_stock_count_path
    assert_select "input[name=scope][value=partial]"
    assert_select "select[name=line] option", /Groceries/
    post stock_counts_path, params: { responsible_id: users(:cashier).id, scope: "partial", line: "Groceries" }
    stock_count = StockCount.last
    assert stock_count.partial?
    assert_equal [ products(:ketchup) ], stock_count.lines.map(&:product)
    post scan_stock_count_path(stock_count), params: { code: "CHKN" }
    assert_match "type it in by hand", flash[:alert]
    post manual_stock_count_path(stock_count), params: { product_id: products(:chicken).id, quantity: "1" }
    assert_match "is not in this partial count", flash[:alert]
    get stock_count_path(stock_count)
    assert_select "span.badge", /partial · 1 product/
    post close_stock_count_path(stock_count)
    assert_equal "closed", stock_count.reload.status
    get stock_counts_path
    assert_select "p", { count: 0, text: /Time to count/ }
    @store.update!(count_interval_days: 3)
    stock_count.update_columns(closed_at: 4.days.ago)
    get stock_counts_path
    assert_select "p", /Time to count/
    get root_path
    assert_select "p", /Time to count/
    post stock_counts_path, params: { responsible_id: users(:cashier).id, scope: "partial" }
    assert_match "at least one product", flash[:alert]
  end

  test "the home page is the dashboard and sales by product with CSV; without permission, a welcome" do
    Till.checkout!(branch: @store, user: users(:cashier), key: "tb", lines: [ { product_id: products(:ketchup).id, quantity: 2 } ], payments: [ { payment_method: "cash", amount_cents: 10_000 } ])
    get root_path
    assert_response :ok
    assert_match "$84.00", response.body
    get sales_by_product_path
    assert_select "td", /Ketchup/
    get sales_by_product_path(format: :csv)
    assert_match "KETC;", response.body
    delete logout_path
    post login_path, params: { user: "cashier", password: "secret12" }
    get root_path
    assert_response :ok
    assert_no_match "$84.00", response.body
    assert_match "Cashier", response.body
    get sales_by_product_path
    assert_response :forbidden
  end
end
