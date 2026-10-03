require "test_helper"

class FeaturesTest < ActionDispatch::IntegrationTest
  setup { post login_path, params: { user: "admin", password: "secret12" } }

  test "by default everything is on and shows in the ribbon" do
    get root_path
    assert_select "aside[data-sidebar-target=panel] div", /Purchasing/
    assert_select "aside[data-sidebar-target=panel] div", /Counts/
  end

  test "turning purchasing off removes it from the ribbon and the roles, and its screens say so" do
    patch settings_system_path, params: { features: [ "warehouses", "stock_counts" ] }
    assert_redirected_to settings_section_path("features")
    assert_not Features.active?("purchases")
    assert Features.active?("stock_counts")

    get root_path
    assert_select "aside[data-sidebar-target=panel] div", { text: /Purchasing/, count: 0 }
    get suppliers_path
    assert_response :not_found
    assert_select "h1", /Purchasing/
    get new_admin_role_path
    assert_select "input[value='purchases.receive']", count: 0
    assert_select "input[value='till.sell']"
  end

  test "a single store starts with purchasing and counts; features are turned on and off from Settings" do
    Features.apply_business_type!("store")
    assert_equal %w[purchases stock_counts], Features.active
    get root_path
    assert_select "aside[data-sidebar-target=panel] div", { text: /Warehouses/, count: 0 }
    patch settings_system_path, params: { features: %w[purchases warehouses stock_counts], back: "features" }
    Current.features = nil
    assert_equal %w[purchases warehouses stock_counts], Features.active
    get settings_section_path("features")
    assert_select "input[data-feature=warehouses]"
  end

  test "a feature with open work is not turned off" do
    StockCount.open!(branch: branches(:store), user: users(:admin), responsible: users(:cashier))
    e = assert_raises(ArgumentError) { Features.store!(%w[purchases warehouses]) }
    assert_match "Counts", e.message
    assert Features.active?("stock_counts")
    Features.store!(%w[purchases warehouses], check: false)
    assert_not Features.active?("stock_counts"), "without checking it is turned off even with open work"
  end
end
