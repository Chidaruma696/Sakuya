require "test_helper"

class OrdersTest < ActionDispatch::IntegrationTest
  setup do
    Features.store!(Features::OPTIONAL, check: false)
    post login_path, params: { user: "supervisor", password: "secret12" }
    @lupita = Customer.create!(name: "Lupita's Diner")
    Inventory.move!(branch: branches(:store), product: products(:ketchup), kind: "inflow", quantity: 10, user: users(:admin))
  end

  test "the order is taken, the till brings it ready and checking it out marks it delivered" do
    get new_order_path
    assert_select "select[name='order[customer_id]'] option", /Lupita's Diner/
    post orders_path, params: { order: { customer_id: @lupita.id, lines_attributes: { "0" => { product_id: "", quantity: "" } } } }
    assert_response :unprocessable_entity
    assert_match "the order has no lines", response.body
    post orders_path, params: { order: { customer_id: @lupita.id, delivery_date: Date.tomorrow, notes: "for lunch",
                                           lines_attributes: { "0" => { product_id: products(:ketchup).id, quantity: "3" } } } }
    order = Order.last
    assert_redirected_to order_path(order)
    assert_equal "P-00001", order.folio
    get orders_path
    assert_select "td", /Ketchup/
    get till_path(order: order.id)
    assert_select "#checking_out_order", /#{order.folio}/
    data = JSON.parse(css_select("[data-pos-order-value]").first["data-pos-order-value"])
    assert_equal [ @lupita.id, products(:ketchup).id, 3.0 ], [ data["customer_id"], data["lines"].first["product_id"], data["lines"].first["quantity"] ]
    post till_checkout_path, params: { key: "ord", customer_id: @lupita.id, order_id: order.id, lines: [ { product_id: products(:ketchup).id, quantity: 3 } ].to_json,
                                     payments: [ { payment_method: "cash", amount_cents: 12_600 } ].to_json }, headers: { "Accept" => "application/json" }
    assert_response :ok
    sale = Sale.find_by!(key: "ord")
    assert_equal [ "delivered", sale, @lupita ], [ order.reload.status, order.sale, sale.customer ]
    get order_path(order)
    assert_select "a", sale.folio
  end

  test "an order is cancelled with a reason and can no longer be checked out" do
    order = Order.create!(customer: @lupita, branch: branches(:store), user: users(:supervisor), lines_attributes: [ { product_id: products(:ketchup).id, quantity: 1 } ])
    post cancel_order_path(order), params: { reason: "" }
    assert_match "reason", flash[:alert]
    post cancel_order_path(order), params: { reason: "they no longer wanted it" }
    assert_equal "cancelled", order.reload.status
    get till_path(order: order.id)
    assert_select "#checking_out_order", 0
    assert_raises(ArgumentError) { order.deliver!(Sale.new) }
  end

  test "the inventory shows what is held and what is available, and the order says whether it holds stock" do
    order = Order.create!(customer: @lupita, branch: branches(:store), user: users(:supervisor), lines_attributes: [ { product_id: products(:ketchup).id, quantity: 4 } ])
    get inventory_path
    assert_select "th", "Held"
    assert_select "tr", /KETC.*10.*4.*6/m
    get order_path(order)
    assert_select ".badge", "holds stock"
    get new_order_path
    assert_select "input[type=checkbox][name='order[reserve]'][checked]"
  end
end
