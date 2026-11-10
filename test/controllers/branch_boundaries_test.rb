require "test_helper"

# What belongs to one branch is not undone from another: the head office reaches everything, a
# store only its own.
class BranchBoundariesTest < ActionDispatch::IntegrationTest
  setup do
    @head_office = branches(:head_office)
    @store = branches(:store)
    @other = Branch.create!(code: "T02", name: "Store 2", kind: "store")
    @ketchup = products(:ketchup)
    roles(:supervisor).update!(permissions: roles(:supervisor).permissions + [ "warehouses.*", "purchases.*" ])
    @outsider = User.create!(name: "Outsider", user: "outsider", password: "secret12", role: roles(:supervisor), branch: @other)
    Inventory.move!(branch: @head_office, product: @ketchup, kind: "inflow", quantity: 50, user: users(:admin))
  end

  def sign_in(user)
    delete logout_path
    post login_path, params: { user: user, password: "secret12" }
  end

  test "a stock transfer is seen and cancelled by the branches it touches and by the head office, nobody else" do
    transfer = StockTransfer.register!(origin: @head_office, destination: @store, user: users(:admin), lines: [ { product_id: @ketchup.id, quantity: 10 } ])

    sign_in "outsider"
    get stock_transfer_path(transfer)
    assert_response :not_found
    post cancel_stock_transfer_path(transfer), params: { reason: "not mine" }
    assert_response :not_found
    assert transfer.reload.registered?
    assert_equal 10, StockLevel.quantity_for(@store, @ketchup)

    sign_in "supervisor" # at the store that received it
    get stock_transfer_path(transfer)
    assert_response :ok
    post cancel_stock_transfer_path(transfer), params: { reason: "came by mistake" }
    assert_redirected_to stock_transfer_path(transfer)
    assert transfer.reload.cancelled?
    assert_equal [ 0, 50 ], [ StockLevel.quantity_for(@store, @ketchup), StockLevel.quantity_for(@head_office, @ketchup) ]

    again = StockTransfer.register!(origin: @head_office, destination: @other, user: users(:admin), lines: [ { product_id: @ketchup.id, quantity: 5 } ])
    sign_in "admin" # at the head office
    post cancel_stock_transfer_path(again), params: { reason: "wrong store" }
    assert again.reload.cancelled?
  end

  test "a receipt is cancelled where it was received or from the head office" do
    supplier = Supplier.create!(name: "Ketchup & Co")
    receipt = Purchases.receive!(branch: @store, supplier: supplier, user: users(:supervisor), lines: [ { product_id: @ketchup.id, quantity: 12 } ])

    sign_in "outsider"
    post cancel_receipt_path(receipt), params: { reason: "not mine" }
    assert_response :not_found
    assert receipt.reload.registered?
    assert_equal 12, StockLevel.quantity_for(@store, @ketchup)

    sign_in "supervisor"
    post cancel_receipt_path(receipt), params: { reason: "wrong supplier" }
    assert_redirected_to receipt_path(receipt)
    assert receipt.reload.cancelled?
    assert_equal 0, StockLevel.quantity_for(@store, @ketchup)

    other = Purchases.receive!(branch: @other, supplier: supplier, user: @outsider, lines: [ { product_id: @ketchup.id, quantity: 3 } ])
    sign_in "admin"
    post cancel_receipt_path(other), params: { reason: "duplicate" }
    assert other.reload.cancelled?
  end

  test "tickets, shifts, orders and stock counts of another branch are not found" do
    Inventory.move!(branch: @store, product: @ketchup, kind: "inflow", quantity: 5, user: users(:cashier))
    sale = Till.checkout!(branch: @store, user: users(:cashier), key: "b1", lines: [ { product_id: @ketchup.id, quantity: 1 } ],
                         payments: [ { payment_method: "cash", amount_cents: 4_200 } ])
    count = StockCount.open!(branch: @store, user: users(:supervisor), responsible: users(:cashier))

    sign_in "outsider"
    [ till_ticket_path(sale), till_escpos_path(sale), till_summary_path(shifts(:store_open)), stock_count_path(count) ].each do |path|
      get path
      assert_response :not_found, path
    end
    post till_create_refund_path, params: { sale_id: sale.id, reason: "x", lines: { sale.lines.first.id => "1" } }
    assert_response :not_found
    post close_stock_count_path(count)
    assert_response :not_found
    get till_refund_path(code: sale.folio)
    assert_select "input[name=sale_id]", count: 0
    assert_equal [ 0, true ], [ Refund.count, count.reload.open? ]
  end
end
