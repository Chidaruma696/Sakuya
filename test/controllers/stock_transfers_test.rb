require "test_helper"

class StockTransfersControllerTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { user: "admin", password: "secret12" }
    @head_office = branches(:head_office)
    @cold = Branch.create!(code: "CLD", name: "Cold storage", kind: "warehouse", cash_limit_cents: 1)
    Inventory.move!(branch: @head_office, product: products(:ketchup), kind: "inflow", quantity: 100, user: users(:admin))
  end

  test "a bulk stock transfer from the screen, and the warehouse ribbon has no till and no labels" do
    get new_stock_transfer_path
    assert_select "option", /Cold storage · warehouse/
    post stock_transfers_path, params: { stock_transfer: { origin_branch_id: @head_office.id, destination_branch_id: @cold.id, date: Date.current, key: "z1",
                                               lines_attributes: { "0" => { product_id: products(:ketchup).id, quantity: "60", boxes: "5" } } } }
    t = StockTransfer.last
    assert_redirected_to stock_transfer_path(t)
    assert_equal 60, StockLevel.quantity_for(@cold, products(:ketchup))
    get stock_transfer_path(t)
    assert_select "h1", /TG-/
    get stock_transfers_path
    assert_select "td", /Cold storage/

    users(:admin).update!(branch: @cold)
    get root_path
    assert_select "aside[data-sidebar-target=panel] div", { text: /Register/, count: 0 }
    assert_select "aside[data-sidebar-target=panel] div", { text: /Labels/, count: 0 }
    assert_select "aside[data-sidebar-target=panel] div", /Warehouses/
  end
end
