require "test_helper"

class InventoryControllerTest < ActionDispatch::IntegrationTest
  test "a cashier without permission does not adjust and gets reported; a supervisor adjusts under their own name" do
    post login_path, params: { user: "cashier", password: "secret12" }
    get inventory_path
    assert_response :ok
    post movements_inventory_path, params: { product_id: products(:chicken).id, kind: "inflow", quantity: "3", reason: "" }
    assert_response :unprocessable_entity, "not without a reason"
    get new_movement_inventory_path
    assert_match "the movement is stopped", response.body
    post movements_inventory_path, params: { product_id: products(:chicken).id, kind: "inflow", quantity: "2", reason: "arrived with nobody around" }
    assert_response :unprocessable_entity
    assert_match "It cannot be moved like this", response.body
    assert_equal BigDecimal("0"), StockLevel.quantity_for(branches(:store), products(:chicken))
    report = Review.last
    assert report.stopped?
    assert_equal [ products(:chicken), 25_800 ], [ report.reviewable, report.value_cents ]
    assert_match "Movement stopped", report.description
    post movements_inventory_path, params: { product_id: products(:chicken).id, kind: "inflow", quantity: "2", reason: "arrived with nobody around" }
    assert_equal 1, Review.count, "the same attempt is not reported twice"
    delete logout_path
    post login_path, params: { user: "supervisor", password: "secret12" }
    post movements_inventory_path, params: { product_id: products(:chicken).id, kind: "inflow", quantity: "1", reason: "arrived" }
    assert_redirected_to kardex_inventory_path(product_id: products(:chicken).id, branch_id: branches(:store).id)
    assert_equal BigDecimal("1"), StockLevel.quantity_for(branches(:store), products(:chicken))
    assert_equal 1, Review.count, "with permission, by default, there is nothing to review"
    assert_match "Supervisor", Movement.last.reason
    follow_redirect!
    assert_select "td", /Entry/
  end

  test "a store cannot look at another branch, the head office can" do
    post login_path, params: { user: "cashier", password: "secret12" }
    get inventory_path(branch_id: branches(:head_office).id)
    assert_select "h1", /Store 1/
    delete logout_path
    post login_path, params: { user: "admin", password: "secret12" }
    get inventory_path(branch_id: branches(:store).id)
    assert_select "h1", /Store 1/
  end

  test "an outgoing adjustment with no stock warns without breaking" do
    post login_path, params: { user: "admin", password: "secret12" }
    post movements_inventory_path, params: { product_id: products(:chicken).id, kind: "waste", quantity: "1", reason: "x" }
    assert_response :unprocessable_entity
    assert_match "Not enough stock", response.body
  end
end
