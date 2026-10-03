# Customers: creation and editing. Their account and orders live elsewhere.
class CustomersController < ApplicationController
  tab :customers
  feature :customers

  before_action { authorize!("customers.view") }
  before_action(only: %i[new create edit update]) { authorize!("customers.edit") }

  def index
    @customers = Customer.order(:name).to_a.sort_by { |c| [ c.active ? 0 : 1, c.name.downcase ] }
    @customers = @customers.select { |c| c.name.downcase.include?(params[:q].to_s.downcase.strip) } if params[:q].present?
    @balances = CreditMovement.group(:customer_id).sum(:amount_cents)
  end

  # Account statement: what they owe, since when, every movement with its running balance, and taking an account payment.
  def account
    @customer = Customer.find(params[:id])
    @account = @customer.account
    balance = 0
    @movements = @account.movements.map { |m| [ m, balance += m.amount_cents ] }.reverse.first(200)
    @shift = Shift.opened_at(current_branch)
  end

  def pay_account
    authorize!("customers.pay_account")
    customer = Customer.find(params[:id])
    account_payment = AccountPayment.register!(customer: customer, branch: current_branch, user: current_user, amount_cents: Money.cents(params[:amount]),
                             payment_method: params[:payment_method].presence_in(Payment::PAYMENT_METHODS) || "cash", notes: params[:notes])
    redirect_to account_customer_path(customer), notice: t("customers.notices.account_payment", folio: account_payment.folio, amount: Money.format_money(account_payment.amount_cents), balance: Money.format_money(customer.balance_cents))
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to account_customer_path(customer), alert: e.message
  end

  def new
    @customer = Customer.new
  end

  def create
    @customer = Customer.new(data)
    if @customer.save
      redirect_to customers_path, notice: t("customers.notices.created", name: @customer.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @customer = Customer.find(params[:id])
  end

  def update
    @customer = Customer.find(params[:id])
    if @customer.update(data)
      redirect_to customers_path, notice: t("customers.notices.saved", name: @customer.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def data
    params.require(:customer).permit(:name, :phone, :tax_id, :address, :notes, :credit_limit, :active)
  end
end
