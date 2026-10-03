# Accounts payable: how much is owed to each supplier, which invoices are coming due, and paying from the till.
class AccountsController < ApplicationController
  tab :purchases
  feature :purchases

  before_action { authorize!("purchases.view") }

  def index
    balances = SupplierMovement.group(:supplier_id).sum(:delta_cents)
    @suppliers = Supplier.where(id: balances.keys).order(:name).map { |p| [ p, balances[p.id] ] }.reject { |_, s| s.zero? }
    @total = @suppliers.sum { |_, s| s }
    @overdue = SupplierInvoice.still_open.includes(:supplier, :payments).where("due < ?", Date.current).order(:due).reject(&:paid?)
    @due_soon = SupplierInvoice.still_open.includes(:supplier, :payments).where(due: Date.current..(Date.current + 7)).order(:due).reject(&:paid?)
  end

  def show
    @supplier = Supplier.find(params[:id])
    @invoices = @supplier.invoices.still_open.includes(:payments).order(date: :desc).limit(100).reject(&:paid?)
    @movements = @supplier.movements.includes(:user, :invoice, :payment).order(id: :desc).limit(200)
    @payments = @supplier.payments.includes(:user, :invoice, :shift).order(id: :desc).limit(50)
    @shift = Shift.opened_at(current_branch)
  end

  def pay
    authorize!("purchases.pay")
    supplier = Supplier.find(params[:id])
    invoice = supplier.invoices.find_by(id: params[:supplier_invoice_id].presence)
    payment = Purchases.pay!(supplier: supplier, branch: current_branch, user: current_user, amount_cents: Money.cents(params[:amount]),
                          payment_method: params[:payment_method].to_s, invoice: invoice, reference: params[:reference])
    redirect_to account_path(supplier), notice: t("purchases.notices.paid", amount: Money.format_money(payment.amount_cents), supplier: supplier.name, balance: Money.format_money(supplier.balance_cents))
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to account_path(supplier), alert: e.message
  end

  def void_payment
    authorize!("purchases.pay")
    payment = SupplierPayment.find(params[:id])
    Purchases.void_payment!(payment, reason: params[:reason].to_s.strip, user: current_user)
    redirect_to account_path(payment.supplier), notice: t("purchases.notices.payment_voided", amount: Money.format_money(payment.amount_cents))
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to account_path(payment.supplier), alert: e.message
  end
end
