# Restocking branches: what each one is short of according to its minimums and maximums, and from
# that a ready-made stock transfer (reviewed and recorded like any other).
class RestockController < ApplicationController
  tab :warehouses
  feature :warehouses

  before_action { authorize!("warehouses.transfer_stock") }

  def index
    @branches = Branch.active.with_till.order(:name).to_a
    @suggested = @branches.to_h { |s| [ s.id, Minimum.suggested(s) ] }
  end

  def minimums
    @branch = Branch.active.find(params[:branch_id])
    @products = Product.active.order(:name)
    @minimums = Minimum.where(branch: @branch).index_by(&:product_id)
    @stock_levels = StockLevel.where(branch: @branch).pluck(:product_id, :quantity).to_h
  end

  def save_minimums
    branch = Branch.active.find(params[:branch_id])
    Minimum.store!(branch, params.fetch(:minimums, {}).to_unsafe_h.transform_values(&:symbolize_keys))
    redirect_to restock_path, notice: t("restock.notices.saved", branch: branch.name)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to restock_minimums_path(branch_id: branch.id), alert: e.message
  end
end
