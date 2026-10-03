require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  setup { post login_path, params: { user: "admin", password: "secret12" } }

  test "products: create, edit, barcodes" do
    get admin_products_path
    assert_select "td", /Chicken breast/
    post admin_products_path, params: { product: { key: "wing", name: "Chicken wing", line: "Poultry", unit: "kg", price: "75.50", active: "1" } }
    assert_redirected_to edit_admin_product_path(Product.find_by!(key: "WING"))
    p = Product.find_by!(key: "WING")
    assert_equal 7_550, p.price_cents
    assert_operator p.plu, :>=, 90_000
    post admin_product_codes_path(p), params: { code: "750 1234 567890" }
    assert_equal "7501234567890", p.product_barcodes.first.code
    delete admin_product_code_path(p, p.product_barcodes.first)
    assert_equal 0, p.product_barcodes.count
    patch admin_product_path(p), params: { product: { key: "WING", name: "Wing", unit: "kg", price: "0", active: "0" } }
    assert_equal false, p.reload.active
    post admin_products_path, params: { product: { key: "", name: "", unit: "kg" } }
    assert_response :unprocessable_entity
    patch admin_product_path(p), params: { product: { key: "WING", name: "Wing", unit: "kg", price: "75.50", active: "1" }, prices: { branches(:store).id => "80", branches(:head_office).id => "" } }
    assert_equal 8_000, p.reload.price_cents_for(branches(:store))
    assert_equal 7_550, p.price_cents_for(branches(:head_office))
    get edit_admin_product_path(p)
    assert_select "input[name='prices[#{branches(:store).id}]'][value='80.0']"
  end

  test "users and roles: create, change role, wildcard permissions" do
    post admin_roles_path, params: { role: { name: "warehouse", permissions: [ "", "purchases.*", "stock_counts.make" ] } }
    role = Role.find_by!(name: "warehouse")
    assert role.allows?("purchases.invoice")
    assert_not role.allows?("till.sell")
    post admin_users_path, params: { user: { name: "Bob", user: "Bob", role_id: role.id, branch_id: branches(:head_office).id, password: "passw1234", active: "1" } }
    u = User.find_by!(user: "bob")
    assert u.authenticate("passw1234")
    patch admin_user_path(u), params: { user: { name: "Bob", user: "bob", role_id: roles(:cashier).id, branch_id: branches(:store).id, password: "", active: "1" } }
    assert u.reload.authenticate("passw1234"), "the password does not change if left blank"
    assert_equal roles(:cashier), u.role
    patch admin_role_path(role), params: { role: { name: "warehouse", permissions: [ "*" ] } }
    assert role.reload.allows?("admin.users")
    get admin_roles_path
    assert_select "td", /warehouse/
  end

  test "promotions: create, list and delete" do
    post admin_promotions_path, params: { promotion: { name: "Tuesday", product_id: products(:ketchup).id, branch_id: "", kind: "price", price: "39.90", minimum_quantity: "", active: "1" } }
    promo = Promotion.last
    assert_redirected_to admin_promotions_path
    assert_equal 3_990, promo.price_cents
    assert_nil promo.branch_id
    get admin_promotions_path
    assert_select "td", /Tuesday/
    get till_scan_path(code: "KETC"), headers: { "Accept" => "application/json" }
    assert_equal "Tuesday", response.parsed_body["promotions"].first["name"]
    delete admin_promotion_path(promo)
    assert_equal 0, Promotion.count
  end

  test "branches with a cash limit in currency, and 403 without permission" do
    post admin_branches_path, params: { branch: { code: "t03", name: "Store 3", kind: "store", cash_limit: "5000", active: "1" } }
    b = Branch.find_by!(code: "T03")
    assert_equal 500_000, b.cash_limit_cents
    delete logout_path
    post login_path, params: { user: "cashier", password: "secret12" }
    get admin_products_path
    assert_response :forbidden
  end
end
