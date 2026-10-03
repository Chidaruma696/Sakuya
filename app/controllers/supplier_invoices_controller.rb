# Supplier invoices: they create the debt. With lines (the price lives only here) or just an amount.
class SupplierInvoicesController < ApplicationController
  tab :purchases
  feature :purchases

  before_action { authorize!("purchases.view") }

  def index
    @invoices = SupplierInvoice.includes(:supplier, :user, :payments, :lines, :receipts).order(date: :desc, id: :desc).limit(200)
    @invoices = @invoices.where(supplier_id: params[:supplier_id]) if params[:supplier_id].present?
    @suppliers = Supplier.order(:name)
  end

  def new
    authorize!("purchases.invoice")
    @invoice = SupplierInvoice.new(date: Date.current, supplier_id: params[:supplier_id])
    @invoice.lines.build
    @suppliers = Supplier.active.order(:name)
    @products = Product.active.order(:name)
    @loose = Receipt.registered.where(supplier_invoice_id: nil).includes(:supplier, :branch).order(date: :desc).limit(60)
    @lock = Setting["purchases.lock_received"] == "1"
  end

  # What is invoiced versus what was received is judged by the invoice rule (InvoiceRule): what it
  # stops is not recorded and gets reported; whoever has purchases.exceed records it with a reason
  # and it is left for review with the excess valued.
  def create
    authorize!("purchases.invoice")
    d = params.require(:invoice)
    supplier = Supplier.active.find(d[:supplier_id])
    lines = (d[:lines_attributes]&.to_unsafe_h || {}).values.map(&:symbolize_keys).reject { |l| l[:product_id].blank? || BigDecimal(l[:quantity].to_s.presence || "0") <= 0 }
    receipts = Receipt.where(id: Array(d[:receipt_ids]), supplier: supplier, supplier_invoice_id: nil, status: "registered").to_a
    excess = Purchases.excess(lines, receipts)
    detail = excess.map { |c| "#{c.product.name} +#{helpers.quantity(-c.difference, c.product)}" }.join(", ")
    value = excess.sum { |c| Money.amount(-c.difference, lines.select { |l| l[:product_id].to_i == c.product.id }.map { |l| Money.cents(l[:price]) }.max.to_i) }
    total = lines.any? ? lines.sum { |l| Money.amount(BigDecimal(l[:quantity].to_s), Money.cents(l[:price])) } : Money.cents(d[:amount])
    with_permission = can?("purchases.exceed")
    decision = InvoiceRule.decide(InvoiceRule::Input.new(excess_items: excess.size, excess_value: value, total: total, receipts: receipts.size,
                                                            supplier: supplier.name, lock: InvoiceRule.lock?, authorized: with_permission, detail: detail))
    failure = (t("invoice_rule.failure", error: decision.error) if decision.error)
    if decision.rejects? && !with_permission
      report = [ t("purchases.invoice_stopped", folio: d[:folio], rule: decision.reason), failure ].compact.join("\n")
      Review.open!(supplier, user: current_user, branch: current_branch, reason: report, value_cents: value, stopped: true)
      raise ArgumentError, t("errors.purchases.invoice_stopped", reason: decision.reason)
    end
    review = !decision.allows? || failure
    raise ArgumentError, t("errors.purchases.missing_reason", reason: decision.reason) if review && !failure && d[:reason].blank?
    invoice = Purchases.invoice!(supplier: supplier, branch: current_branch, user: current_user, folio: d[:folio].to_s, date: Date.parse(d[:date].presence || Date.current.to_s),
                                due: (Date.parse(d[:due]) if d[:due].present?), concept: d[:concept], amount_cents: Money.cents(d[:amount]), lines: lines)
    receipts.each { |r| Purchases.link!(r, invoice) }
    if review
      reason = [ ("#{d[:reason]} (#{detail})" if d[:reason].present?), (decision.reason unless decision.allows?), failure ].compact.uniq.join("\n")
      Review.open!(invoice, user: current_user, branch: current_branch, reason: reason, value_cents: value)
    end
    redirect_to invoice_path(invoice), notice: t("purchases.notices.invoiced", folio: invoice.folio, amount: Money.format_money(invoice.amount_cents)) + (review ? t("till.notices.remains_pending_review") : "")
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    redirect_to new_invoice_path(supplier_id: d && d[:supplier_id]), alert: e.message
  end

  def show
    @invoice = SupplierInvoice.includes(:supplier, :user, lines: :product, receipts: %i[user branch], payments: %i[user withdrawal]).find(params[:id])
    @comparison = Purchases.comparison(@invoice)
    @loose = @invoice.supplier.receipts.registered.where(supplier_invoice_id: nil).order(date: :desc).limit(30)
  end

  def cancel
    authorize!("purchases.invoice")
    invoice = SupplierInvoice.find(params[:id])
    Purchases.cancel_invoice!(invoice, reason: params[:reason].to_s.strip, user: current_user)
    redirect_to invoice_path(invoice), notice: t("purchases.notices.invoice_cancelled", folio: invoice.folio)
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to invoice_path(invoice), alert: e.message
  end
end
