class InventoryController < ApplicationController
  tab :inventory

  before_action(except: :search) { authorize!("inventory.view") }
  before_action :load_branch, except: :search

  # Whatever was scanned or typed: supplier code, PLU, key or name (JSON, for the line-item
  # forms: receipt, invoice, bulk stock transfer).
  def search
    q = params[:q].to_s.strip
    scanned = Scan.resolve(q)
    products = if scanned&.product && scanned.product.active
      [ scanned.product ]
    else
      Product.active.where("LOWER(name) LIKE :q OR LOWER(key) LIKE :q", q: "%#{q.downcase}%").order(:name).limit(10)
    end
    render json: products.map { |p| { id: p.id, name: p.name, unit: p.unit } }
  end

  def index
    @stock_levels = StockLevel.where(branch: @branch).includes(:product)
                             .joins(:product).order("products.name")
    @reserved = Reservations.by_product(@branch)
  end

  def kardex
    @product = Product.find_by(id: params[:product_id])
    @movements = Movement.where(branch: @branch).includes(:product, :user)
                             .order(created_at: :desc).limit(200)
    @movements = @movements.where(product: @product) if @product
  end

  def new_movement
    @movement = Movement.new(kind: "inflow")
  end

  # The movement is judged by the movement rule (MovementRule): what it stops does not move and
  # gets reported, unless someone with inventory.adjust does it (then it is left for review).
  def create_movement
    return back_with_error(t("errors.writes_reason")) if params[:reason].blank?
    product = Product.active.find(params[:product_id])
    kind = params[:kind].presence_in(MovementRule::KINDS.keys) || "inflow"
    decision = MovementRule.decide(branch: @branch, product: product, kind: kind, quantity: params[:quantity], reason: params[:reason], user: current_user)
    failure = (t("movement_rule.failure", error: decision.error) if decision.error)
    with_permission = can?("inventory.adjust")
    if decision.rejects? && !with_permission
      report = [ t("inventory.movement_stopped", kind: t("movements.#{kind}"), quantity: params[:quantity], reason: params[:reason], rule: decision.reason), failure ].compact.join("\n")
      Review.open!(product, user: current_user, branch: @branch, reason: report, stopped: true,
                      value_cents: Review.value(BigDecimal(params[:quantity].to_s), product, @branch))
      return back_with_error(t("errors.inventory.movement_stopped", reason: decision.reason))
    end
    review = decision.allows? && !failure ? nil : [ params[:reason], (decision.reason unless decision.allows?), failure ].compact.join("\n")
    note = if review then " (#{t("common.pending_review")})" elsif with_permission then " (#{t("common.authorized")} #{current_user.name})" end
    movement = Inventory.move!(branch: @branch, product: product, kind: kind, quantity: params[:quantity], user: current_user,
                                   reason: "#{params[:reason]}#{note}")
    if review
      Review.open!(movement, user: current_user, branch: @branch, reason: review, value_cents: Review.value(movement.quantity, product, @branch))
    end
    redirect_to kardex_inventory_path(product_id: product.id, branch_id: @branch.id),
                notice: t("inventory.movement_recorded", kind: t("movements.#{kind}"), product: product.name) + (review ? t("till.notices.remains_pending_review") : "")
  rescue Inventory::OutOfStock, ArgumentError => e
    back_with_error(e.message)
  end

  private

  # The head office can look at any branch; a store only at its own.
  def load_branch
    @branch = current_branch
    if params[:branch_id].present? && (current_branch.head_office? || can?("admin.users"))
      @branch = Branch.find(params[:branch_id])
    end
  end

  def back_with_error(message)
    @movement = Movement.new(kind: params[:kind], product_id: params[:product_id], quantity: params[:quantity], reason: params[:reason])
    flash.now[:alert] = message
    render :new_movement, status: :unprocessable_entity
  end
end
