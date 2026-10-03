require "test_helper"

# Forms with rows have to send lines_attributes, which is what their controllers read. The test
# reads what each form really renders, not what the test assumes.
class RowFormsTest < ActionDispatch::IntegrationTest
  setup do
    Features.store!(Features::OPTIONAL, check: false)
    post login_path, params: { user: "admin", password: "secret12" }
  end

  { stock_transfer: :new_stock_transfer_path, receipt: :new_receipt_path, invoice: :new_invoice_path, order: :new_order_path }.each do |model, route|
    test "the #{model} form names its rows lines_attributes" do
      get send(route)
      names = css_select("[name*='[product_id]']").map { |e| e["name"] }
      assert names.any?, "there are no rows"
      assert names.all? { |n| n.match?(/\A\w+\[lines_attributes\]\[\d+\]\[product_id\]\z/) }, names.inspect
    end
  end

  test "a stock transfer built from what the form renders does get recorded" do
    Inventory.move!(branch: branches(:head_office), product: products(:ketchup), kind: "inflow", quantity: 5, user: users(:admin))
    get new_stock_transfer_path
    product = css_select("select[name*='[product_id]']").first["name"]
    quantity = css_select("input[name*='[quantity]']").first["name"]
    post stock_transfers_path, params: { "stock_transfer[origin_branch_id]" => branches(:head_office).id, "stock_transfer[destination_branch_id]" => branches(:store).id,
                                   product => products(:ketchup).id, quantity => "2", "stock_transfer[key]" => "f" }
    assert_redirected_to stock_transfer_path(StockTransfer.last)
    assert_equal BigDecimal("2"), StockLevel.quantity_for(branches(:store), products(:ketchup))
  end

  test "a receipt and an invoice built from what the form renders do get recorded" do
    supplier = Supplier.create!(name: "Farm", credit_days: 0)
    get new_receipt_path
    fields = ->(sel) { css_select(sel).first["name"] }
    post receipts_path, params: { "receipt[supplier_id]" => supplier.id, "receipt[key]" => "r",
                                     fields.("select[name*='[product_id]']") => products(:ketchup).id, fields.("input[name*='[quantity]']") => "4" }
    assert_redirected_to receipt_path(Receipt.last)
    assert_equal 1, Receipt.last.lines.count
    get new_invoice_path
    post invoices_path, params: { "invoice[supplier_id]" => supplier.id, "invoice[folio]" => "F-1", "invoice[date]" => Date.current, "invoice[receipt_ids][]" => Receipt.last.id,
                                  fields.("select[name*='[product_id]']") => products(:ketchup).id, fields.("input[name*='[quantity]']") => "4", fields.("input[name*='[price]']") => "30" }
    assert_redirected_to invoice_path(SupplierInvoice.last)
    assert_equal 12_000, SupplierInvoice.last.amount_cents
  end
end
