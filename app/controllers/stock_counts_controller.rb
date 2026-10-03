class StockCountsController < ApplicationController
  tab :stock_counts
  feature :stock_counts

  before_action { authorize!("stock_counts.make") }
  before_action :load_stock_count, only: %i[show scan manual close]

  def index
    @stock_counts = StockCount.where(branch: current_branch).includes(:user, :responsible, :lines).order(created_at: :desc).limit(30)
    @overdue = StockCount.overdue?(current_branch)
  end

  def new
    @open = StockCount.still_open.find_by(branch: current_branch)
    @responsible = User.active.where(branch: current_branch).order(:name)
    @lines = Product.active.where.not(line: [ nil, "" ]).distinct.order(:line).pluck(:line)
    @products = Product.active.order(:name)
  end

  # Everything, or just one product line or a few products (partial): the rest is left alone on closing.
  def create
    products = if params[:scope] == "partial"
      params[:line].present? ? Product.active.where(line: params[:line]).order(:name).to_a : Product.active.where(id: params[:product_ids]).order(:name).to_a
    end
    stock_count = StockCount.open!(branch: current_branch, user: current_user, responsible: User.active.find(params[:responsible_id]), products: products)
    redirect_to stock_count_path(stock_count), notice: t("stock_counts.notices.open", folio: stock_count.folio)
  rescue ArgumentError => e
    redirect_to new_stock_count_path, alert: e.message
  end

  def show
    @lines = @stock_count.lines.includes(:product).joins(:product).order("products.name")
    @products = @stock_count.partial? ? @lines.map(&:product) : Product.active.order(:name)
  end

  def scan
    product = Scan.resolve(params[:code])&.product or raise ArgumentError, t("errors.stock_count.not_found", code: params[:code])
    @stock_count.scan!(product)
    redirect_to stock_count_path(@stock_count), notice: t("stock_counts.notices.counted", product: product.name)
  rescue ArgumentError => e
    redirect_to stock_count_path(@stock_count), alert: e.message
  end

  def manual
    product = Product.active.find(params[:product_id])
    @stock_count.count_manual!(product, params[:quantity])
    redirect_to stock_count_path(@stock_count), notice: t("stock_counts.notices.counted_manual", product: product.name, quantity: params[:quantity])
  rescue ArgumentError => e
    redirect_to stock_count_path(@stock_count), alert: e.message
  end

  def close
    @stock_count.close!(user: current_user)
    notice = t("stock_counts.notices.closed", folio: @stock_count.folio, shortage: Money.format_money(@stock_count.shortage_cents), surplus: Money.format_money(@stock_count.surplus_cents))
    notice += t("stock_counts.notices.charge_to", responsible: @stock_count.responsible) if @stock_count.shortage_cents.positive?
    redirect_to stock_count_path(@stock_count), notice: notice
  rescue ArgumentError, Inventory::OutOfStock => e
    redirect_to stock_count_path(@stock_count), alert: e.message
  end

  private

  def load_stock_count
    @stock_count = StockCount.where(branch: current_branch).find(params[:id])
  end
end
