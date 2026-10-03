# Suppliers: creation and editing. What they are owed lives in Accounts.
class SuppliersController < ApplicationController
  tab :purchases
  feature :purchases

  before_action { authorize!("purchases.view") }
  before_action(only: %i[new create edit update]) { authorize!("purchases.invoice") }

  def index
    @suppliers = Supplier.order(:active, :name).reverse_order.includes(:movements).to_a.sort_by { |p| [ p.active ? 0 : 1, p.name.downcase ] }
    @balances = SupplierMovement.group(:supplier_id).sum(:delta_cents)
  end

  def new
    @supplier = Supplier.new
  end

  def create
    @supplier = Supplier.new(data)
    if @supplier.save
      redirect_to suppliers_path, notice: t("purchases.notices.supplier_created", name: @supplier.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @supplier = Supplier.find(params[:id])
  end

  def update
    @supplier = Supplier.find(params[:id])
    if @supplier.update(data)
      redirect_to suppliers_path, notice: t("purchases.notices.supplier_saved", name: @supplier.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def data
    params.require(:supplier).permit(:name, :tax_id, :contact, :phone, :credit_days, :notes, :active)
  end
end
