require "test_helper"

class RestockTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { user: "admin", password: "secret12" }
    @store = branches(:store)
    Inventory.move!(branch: @store, product: products(:ketchup), kind: "inflow", quantity: 2, user: users(:admin))
    Inventory.move!(branch: branches(:head_office), product: products(:ketchup), kind: "inflow", quantity: 50, user: users(:admin))
    Inventory.move!(branch: branches(:head_office), product: products(:chicken), kind: "inflow", quantity: 50, user: users(:admin))
  end

  test "with minimums and maximums it suggests what is missing and builds the stock transfer" do
    get restock_path
    assert_select "#branch_#{@store.id}", /nothing missing/
    patch restock_minimums_path(branch_id: @store.id), params: { minimums: {
      products(:ketchup).id => { minimum: "5", maximum: "12" },
      products(:chicken).id => { minimum: "1.5", maximum: "" }
    } }
    assert_redirected_to restock_path
    assert_equal [ [ products(:ketchup), 10 ], [ products(:chicken), BigDecimal("1.5") ] ].sort_by { |p, _| p.name },
                 Minimum.suggested(@store).map { |p, c| [ p, c ] }
    get restock_path
    assert_select "#branch_#{@store.id}", /2 products missing/
    get new_stock_transfer_path(destination: @store.id, suggested: 1)
    assert_select "select[name='stock_transfer[destination_branch_id]'] option[selected][value=?]", @store.id.to_s
    assert_select "input[name$='[quantity]'][value='10']"
    assert_select "input[name$='[quantity]'][value='1.5']"
    patch restock_minimums_path(branch_id: @store.id), params: { minimums: { products(:chicken).id => { minimum: "" } } }
    assert_equal [ products(:ketchup) ], Minimum.where(branch: @store).map(&:product)
    patch restock_minimums_path(branch_id: @store.id), params: { minimums: { products(:ketchup).id => { minimum: "5", maximum: "3" } } }
    assert flash[:alert].present?, "a maximum below the minimum is not saved"
    assert_equal 12, Minimum.find_by(branch: @store, product: products(:ketchup)).maximum
  end
end
