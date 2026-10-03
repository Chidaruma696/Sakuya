# Customer orders: taken here and charged at the till ("Check out at the till" builds the ticket).
class OrdersController < ApplicationController
  tab :customers
  feature :customers

  before_action { authorize!("customers.view") }
  before_action(only: %i[new create cancel]) { authorize!("customers.orders") }

  def index
    @status = params[:status].presence_in(Order::STATUSES) || "open"
    @orders = Order.where(branch: current_branch, status: @status).includes(:customer, :user, lines: :product)
                     .order(Arel.sql("delivery_date IS NULL"), :delivery_date, :id).limit(200)
  end

  def new
    @order = Order.new(customer_id: params[:customer_id])
    @order.lines.build
    load_lists
  end

  def create
    @order = Order.new(params.require(:order).permit(:customer_id, :delivery_date, :notes, :reserve, lines_attributes: %i[product_id quantity]))
    @order.assign_attributes(branch: current_branch, user: current_user)
    @order.customer = Customer.active.find_by(id: @order.customer_id)
    if @order.save
      redirect_to order_path(@order), notice: t("orders.notices.created", folio: @order.folio, customer: @order.customer)
    else
      @order.lines.build if @order.lines.empty?
      load_lists
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @order = Order.where(branch: current_branch).includes(:customer, :sale, lines: :product).find(params[:id])
  end

  def cancel
    order = Order.where(branch: current_branch).find(params[:id])
    order.cancel!(reason: params[:reason].to_s.strip)
    redirect_to order_path(order), notice: t("orders.notices.cancelled", folio: order.folio)
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to order_path(order), alert: e.message
  end

  private

  def load_lists
    @customers = Customer.active.order(:name)
    @products = Product.active.order(:name)
  end
end
