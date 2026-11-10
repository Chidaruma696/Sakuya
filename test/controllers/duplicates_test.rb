require "test_helper"

# The same thing sent twice (a double click, a retry, the same user on two screens) is recorded
# once: every form that moves money carries a key, and the database refuses the rest.
class DuplicatesTest < ActionDispatch::IntegrationTest
  setup do
    SessionsController::ATTEMPTS.clear
    @store = branches(:store)
    @ketchup = products(:ketchup)
    roles(:supervisor).update!(permissions: roles(:supervisor).permissions + [ "purchases.*" ])
    Setting.store!("features.customers" => "1")
    Inventory.move!(branch: @store, product: @ketchup, kind: "inflow", quantity: 20, user: users(:supervisor))
    post login_path, params: { user: "supervisor", password: "secret12" }
  end

  def checkout(key, **extra)
    post till_checkout_path, params: { key: key, lines: [ { product_id: @ketchup.id, quantity: 2 } ].to_json,
                                       payments: [ { payment_method: "cash", amount_cents: 8_400 } ].to_json, **extra }
  end

  test "every form that moves money carries its own key, a new one each time the page loads" do
    customer = Customer.create!(name: "Ana")
    supplier = Supplier.create!(name: "Ketchup & Co")
    Purchases.invoice!(supplier: supplier, branch: @store, user: users(:supervisor), folio: "F-1", date: Date.current, amount_cents: 50_000)
    checkout("k0")
    { till_shift_path => till_withdraw_path, account_customer_path(customer) => pay_account_customer_path(customer),
      account_path(supplier) => pay_account_path(supplier), till_refund_path(code: Sale.last.folio) => till_create_refund_path }.each do |page, action|
      keys = 2.times.map do
        get page
        assert_response :ok
        assert_select("form[action='#{action}'][method=post] input[type=hidden][name=key]", 1, page).first["value"]
      end
      assert keys.all?(&:present?) && keys.uniq.size == 2, page
    end
  end

  test "a withdrawal sent twice comes out of the drawer once" do
    2.times { post till_withdraw_path, params: { key: "w1", amount: "100", reason: "to the safe" } }
    assert_redirected_to till_shift_path
    assert_match "$100.00", flash[:notice]
    assert_equal [ 1, 40_000 ], [ Withdrawal.count, shifts(:store_open).expected_cash_cents ]
    post till_withdraw_path, params: { key: "w2", amount: "100", reason: "to the safe" }
    assert_equal [ 2, 30_000 ], [ Withdrawal.count, shifts(:store_open).expected_cash_cents ], "another key is another withdrawal"
  end

  test "a customer's payment sent twice is taken once" do
    customer = Customer.create!(name: "Ana")
    customer.credit_movements.create!(kind: "charge", amount_cents: 50_000, date: Date.current, branch: @store, user: users(:supervisor))
    2.times { post pay_account_customer_path(customer), params: { key: "a1", amount: "200", payment_method: "cash" } }
    assert_redirected_to account_customer_path(customer)
    assert_equal [ 1, 30_000, 70_000 ], [ AccountPayment.count, customer.balance_cents, shifts(:store_open).expected_cash_cents ]
  end

  test "a supplier payment sent twice is paid once" do
    supplier = Supplier.create!(name: "Ketchup & Co")
    Purchases.invoice!(supplier: supplier, branch: @store, user: users(:supervisor), folio: "F-1", date: Date.current, amount_cents: 50_000)
    2.times { post pay_account_path(supplier), params: { key: "s1", amount: "200", payment_method: "cash" } }
    assert_redirected_to account_path(supplier)
    assert_equal [ 1, 1, 30_000, 30_000 ], [ SupplierPayment.count, Withdrawal.count, supplier.reload.balance_cents, shifts(:store_open).expected_cash_cents ]
  end

  test "a refund sent twice gives the money back once" do
    checkout("k1")
    sale = Sale.last
    2.times { post till_create_refund_path, params: { key: "r1", sale_id: sale.id, reason: "dented", lines: { sale.lines.first.id => "1" } } }
    assert_redirected_to till_sales_path
    assert_equal [ 1, 4_200, BigDecimal("19") ], [ Refund.count, sale.total_refunded_cents, StockLevel.quantity_for(@store, @ketchup) ]
    post till_create_refund_path, params: { key: "r2", sale_id: sale.id, reason: "dented too", lines: { sale.lines.first.id => "1" } }
    assert_equal [ 2, "refunded" ], [ Refund.count, sale.reload.status ]
    post till_create_refund_path, params: { key: "r3", sale_id: sale.id, reason: "once more", lines: { sale.lines.first.id => "1" } }
    assert_equal 2, Refund.count, "nothing is left to give back"
  end

  test "a ticket sent twice is one sale, and an order is delivered with its sale and only once" do
    2.times { checkout("k1") }
    assert_response :ok
    assert_equal [ 1, BigDecimal("18") ], [ Sale.count, StockLevel.quantity_for(@store, @ketchup) ]

    customer = Customer.create!(name: "Ana")
    order = Order.create!(customer: customer, branch: @store, user: users(:supervisor), lines_attributes: [ { product_id: @ketchup.id, quantity: 2 } ])
    checkout("k2", order_id: order.id, customer_id: customer.id)
    assert_response :ok
    assert_equal [ "delivered", Sale.find_by!(key: "k2") ], [ order.reload.status, order.sale ]
    checkout("k3", order_id: order.id, customer_id: customer.id) # the same order from another screen, with its own key
    assert_equal 3, Sale.count, "the till no longer finds it open, so it is an ordinary sale and the order stays with its own"
    assert_equal Sale.find_by!(key: "k2"), order.reload.sale
    # Straight at the door: an order that is no longer open is refused and nothing is charged.
    error = assert_raises(Till::Error) do
      Till.checkout!(branch: @store, user: users(:supervisor), key: "k4", order: order, lines: [ { product_id: @ketchup.id, quantity: 1 } ],
                     payments: [ { payment_method: "cash", amount_cents: 4_200 } ])
    end
    assert_match "is no longer open", error.message
    assert_nil Sale.find_by(key: "k4")
  end

  test "opening the till twice leaves one shift, and so does opening a count twice" do
    delete logout_path
    post login_path, params: { user: "admin", password: "secret12" } # at the head office, with no shift open
    2.times { post till_open_path, params: { float: "500" } }
    assert_redirected_to till_shift_path
    assert_match "already an open register session", flash[:alert]
    assert_equal 1, Shift.still_open.where(branch: branches(:head_office)).count
    2.times { post stock_counts_path, params: { responsible_id: users(:admin).id } }
    assert_match "already an open count", flash[:alert]
    assert_equal 1, StockCount.still_open.count
  end
end
