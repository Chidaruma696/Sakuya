require "test_helper"

# Purchasing screens: ribbon, adding a supplier, receiving by scanning the supplier's barcode,
# linked invoice, accounts payable paid from the drawer, and the feature turned off.
class PurchasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { user: "admin", password: "secret12" }
    @head_office = branches(:head_office)
  end

  test "the full flow: supplier, receipt by barcode, linked invoice and payment" do
    get root_path
    assert_select "aside[data-sidebar-target=panel] div", /Purchasing/

    post suppliers_path, params: { supplier: { name: "Ketchup & Co", credit_days: 30, phone: "555" } }
    supplier = Supplier.find_by!(name: "Ketchup & Co")
    assert_redirected_to suppliers_path

    get search_products_path(q: "750100655901"), headers: { "Accept" => "application/json" }
    list = JSON.parse(response.body)
    assert_equal [ products(:ketchup).id ], list.map { |p| p["id"] }, "the supplier's barcode resolves the product"

    post receipts_path, params: { receipt: { supplier_id: supplier.id, delivery_note: "R-1", date: Date.current, key: "k1",
                                                  lines_attributes: { "0" => { product_id: products(:ketchup).id, quantity: "12", boxes: "1" } } } }
    r = Receipt.last
    assert_redirected_to receipt_path(r)
    assert_equal 12, StockLevel.quantity_for(@head_office, products(:ketchup))
    get receipt_path(r)
    assert_select "h1", /RC-/
    assert_select "td", /Ketchup/

    post invoices_path, params: { invoice: { supplier_id: supplier.id, folio: "B-9", date: Date.current, receipt_ids: [ r.id ],
                                             lines_attributes: { "0" => { product_id: products(:ketchup).id, quantity: "12", price: "25" } } } }
    f = SupplierInvoice.last
    assert_redirected_to invoice_path(f)
    assert_equal 300_00, f.amount_cents
    assert_equal f, r.reload.invoice
    get invoice_path(f)
    assert_select "td", /✓/

    get accounts_path
    assert_select "td", /Ketchup & Co/
    get account_path(supplier)
    assert_select "p", /No till open/
    Shift.open!(branch: @head_office, user: users(:admin), float_cents: 500_00)
    post pay_account_path(supplier), params: { amount: "300", payment_method: "cash", supplier_invoice_id: f.id }
    assert_redirected_to account_path(supplier)
    assert_equal 0, supplier.balance_cents
    assert_equal 200_00, Shift.opened_at(@head_office).expected_cash_cents
  end

  test "purchasing lock, on by default: over-invoicing is stopped and reported; with permission it asks for a reason and goes to review" do
    supplier = Supplier.create!(name: "Farm", credit_days: 0)
    r = Purchases.receive!(branch: @head_office, supplier: supplier, user: users(:admin), lines: [ { product_id: products(:ketchup).id, quantity: "12" } ])
    lines = { "0" => { product_id: products(:ketchup).id, quantity: "15", price: "30" } }
    get settings_section_path("purchases")
    assert_select "input[name='setting[purchases.lock_received]'][checked]", 1, "on by default"
    # Without the lock only the difference is shown.
    Setting.store!("purchases.lock_received" => "0")
    post invoices_path, params: { invoice: { supplier_id: supplier.id, folio: "F-1", date: Date.current, receipt_ids: [ r.id ], lines_attributes: lines } }
    assert_redirected_to invoice_path(SupplierInvoice.last)
    assert_equal 0, Review.count
    assert_equal "partial", SupplierInvoice.last.receipt_status
    Setting.store!("purchases.lock_received" => "1")
    # The admin has purchases.exceed: it is recorded, but with a reason, and goes to review.
    post invoices_path, params: { invoice: { supplier_id: supplier.id, folio: "F-2", date: Date.current, lines_attributes: lines } }
    assert_match "more than received (Ketchup 1 kg +15 pc): write the reason", flash[:alert]
    post invoices_path, params: { invoice: { supplier_id: supplier.id, folio: "F-2", date: Date.current, reason: "arrives tomorrow", lines_attributes: lines } }
    f = SupplierInvoice.find_by!(folio: "F-2")
    assert_redirected_to invoice_path(f)
    assert_match "goes to review", flash[:notice]
    assert_equal "no_receipt", f.receipt_status
    rev = Review.last
    assert_equal [ f, 45_000 ], [ rev.reviewable, rev.value_cents ], "15 too many × 30.00"
    assert_match "arrives tomorrow (Ketchup 1 kg +15 pc)", rev.reason
    assert_match "with more than received", rev.description
    # Without the permission it is not recorded and the attempt is reported.
    roles(:administrator).update!(permissions: Permission::KEYS.keys - [ "purchases.exceed" ])
    get new_invoice_path
    assert_select "input[name='invoice[reason]']"
    assert_select "input[name='invoice[receipt_ids][]']", { count: 0 }, "the receipt is already linked to F-1"
    r2 = Purchases.receive!(branch: @head_office, supplier: supplier, user: users(:admin), lines: [ { product_id: products(:ketchup).id, quantity: "10" } ])
    post invoices_path, params: { invoice: { supplier_id: supplier.id, folio: "F-3", date: Date.current, receipt_ids: [ r2.id ], reason: "the supplier charges for the waste", lines_attributes: lines } }
    assert_match "It cannot be recorded like this", flash[:alert]
    assert_nil SupplierInvoice.find_by(folio: "F-3")
    rev = Review.last
    assert rev.stopped?
    assert_equal [ supplier, 15_000 ], [ rev.reviewable, rev.value_cents ], "5 too many × 30.00"
    assert_match "Invoice F-3 stopped", rev.reason
    assert_match "Invoice stopped from Farm", rev.description
    r3 = Purchases.receive!(branch: @head_office, supplier: supplier, user: users(:admin), lines: [ { product_id: products(:ketchup).id, quantity: "5" } ])
    post invoices_path, params: { invoice: { supplier_id: supplier.id, folio: "F-3", date: Date.current, receipt_ids: [ r2.id, r3.id ], lines_attributes: lines } }
    assert_equal "complete", SupplierInvoice.find_by!(folio: "F-3").receipt_status, "with the missing receipt linked, it goes through"
    post invoices_path, params: { invoice: { supplier_id: supplier.id, folio: "F-4", date: Date.current, amount: "80" } }
    assert_equal "complete", SupplierInvoice.find_by!(folio: "F-4").receipt_status, "without lines there is nothing to compare"
    get invoices_path
    assert_select "span", /partially received/
    assert_select "span", /no receipt/
  end

  test "with the feature off its screens say so and it disappears from the ribbon" do
    Features.store!(Features::OPTIONAL - %w[purchases], check: false)
    get root_path
    assert_select "aside[data-sidebar-target=panel] div", { text: /Purchasing/, count: 0 }
    get suppliers_path
    assert_response :not_found

    Features.store!(Features::OPTIONAL - %w[warehouses], check: false)
    get root_path
    assert_select "aside[data-sidebar-target=panel] div", { text: /Warehouses/, count: 0 }
    assert_select "aside[data-sidebar-target=panel] div", /Purchasing/
    get new_stock_transfer_path
    assert_response :not_found
    get new_admin_branch_path
    assert_select "option", { text: /Warehouse/, count: 0 }
  ensure
    Features.store!(Features::OPTIONAL, check: false)
  end

  test "the cashier cannot get into purchasing" do
    post login_path, params: { user: "cashier", password: "secret12" }
    get accounts_path
    assert_response :forbidden
  end
end
