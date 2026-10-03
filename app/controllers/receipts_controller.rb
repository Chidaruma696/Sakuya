# Receiving goods from a supplier: scan or pick the product, note how much arrived, and it goes
# into stock. The invoice is linked when it arrives.
class ReceiptsController < ApplicationController
  tab :purchases
  feature :purchases

  before_action { authorize!("purchases.view") }

  def index
    @receipts = Receipt.where(branch: current_branch).includes(:supplier, :user, :invoice, lines: :product).order(created_at: :desc).limit(100)
  end

  def new
    authorize!("purchases.receive")
    @receipt = Receipt.new(date: Date.current)
    @receipt.lines.build
    @suppliers = Supplier.active.order(:name)
    @products = Product.active.order(:name)
    @key = SecureRandom.hex(8)
  end

  # What arrives is judged by the receipt rule (ReceiptRule): what it stops does not come in and gets
  # reported on the supplier; with purchases.force_receipt it comes in and is left for review.
  def create
    authorize!("purchases.receive")
    d = params.require(:receipt)
    supplier = Supplier.active.find(d[:supplier_id])
    invoice = supplier.invoices.still_open.find_by(id: d[:supplier_invoice_id].presence)
    lines = (d[:lines_attributes]&.to_unsafe_h || {}).values
    if d[:key].blank? || !Receipt.exists?(branch: current_branch, key: d[:key])
      review = judge(supplier, lines, d[:delivery_note], invoice.present?)
    end
    receipt = Purchases.receive!(branch: current_branch, supplier: supplier, user: current_user, delivery_note: d[:delivery_note], invoice: invoice,
                                 notes: d[:notes], date: d[:date].presence || Date.current, key: d[:key], lines: lines)
    Review.open!(receipt, user: current_user, branch: current_branch, reason: review, value_cents: @value) if review
    redirect_to receipt_path(receipt), notice: t("purchases.notices.received", folio: receipt.folio) + (review ? t("till.notices.remains_pending_review") : "")
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    redirect_to new_receipt_path, alert: e.message
  end

  def show
    @receipt = Receipt.includes(:supplier, :user, :invoice, lines: :product).find(params[:id])
    @invoices = @receipt.supplier.invoices.still_open.order(date: :desc).limit(50)
  end

  def cancel
    authorize!("purchases.receive")
    receipt = Receipt.find(params[:id])
    Purchases.cancel_receipt!(receipt, reason: params[:reason].to_s.strip, user: current_user)
    redirect_to receipt_path(receipt), notice: t("purchases.notices.receipt_cancelled", folio: receipt.folio)
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to receipt_path(receipt), alert: e.message
  end

  # Link (or unlink) the supplier invoice.
  def invoice
    authorize!("purchases.invoice")
    receipt = Receipt.find(params[:id])
    invoice = receipt.supplier.invoices.find_by(id: params[:supplier_invoice_id].presence)
    Purchases.link!(receipt, invoice)
    redirect_to receipt_path(receipt), notice: invoice ? t("purchases.notices.linked", folio: invoice.folio) : t("purchases.notices.unlinked")
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to receipt_path(receipt), alert: e.message
  end

  private

  # Returns the reason to review it (or nil); if the rule stops it and there is no permission, reports and raises.
  def judge(supplier, lines, delivery_note, invoiced)
    with_permission = can?("purchases.force_receipt")
    data = ReceiptRule.data(branch: current_branch, supplier: supplier, lines: lines, delivery_note: delivery_note, invoiced: invoiced, authorized: with_permission)
    @value = data.value
    decision = ReceiptRule.decide(data)
    failure = (t("receipt_rule.failure", error: decision.error) if decision.error)
    if decision.rejects? && !with_permission
      report = [ t("purchases.receipt_stopped", reason: decision.reason), failure ].compact.join("\n")
      Review.open!(supplier, user: current_user, branch: current_branch, reason: report, value_cents: @value, stopped: true)
      raise ArgumentError, t("errors.purchases.receipt_stopped", reason: decision.reason)
    end
    [ (decision.reason unless decision.allows?), failure ].compact.join("\n").presence
  end
end
