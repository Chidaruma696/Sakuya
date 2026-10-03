# Stock transfers: goods from one branch to another. The way in and out of
# warehouses.
class StockTransfersController < ApplicationController
  tab :warehouses
  feature :warehouses

  before_action { authorize!("warehouses.transfer_stock") }

  def index
    @stock_transfers = StockTransfer.where("origin_branch_id = :s OR destination_branch_id = :s", s: current_branch.id)
                         .includes(:origin_branch, :destination_branch, :user, lines: :product).order(created_at: :desc).limit(100)
  end

  # With ?destination=ID&suggested=1 it arrives prefilled with what that branch needs to restock.
  def new
    @stock_transfer = StockTransfer.new(date: Date.current, origin_branch: current_branch, destination_branch_id: params[:destination])
    if params[:suggested].present? && (destination = Branch.active.find_by(id: params[:destination]))
      Minimum.suggested(destination).each { |product, quantity| @stock_transfer.lines.build(product: product, quantity: quantity) }
      @stock_transfer.notes = t("restock.note_stock_transfer")
    end
    @stock_transfer.lines.build if @stock_transfer.lines.empty?
    @origins = current_branch.head_office? ? Branch.active.order(:name) : [ current_branch ]
    @destinations = Branch.active.order(:name)
    @products = Product.active.order(:name)
    @key = SecureRandom.hex(8)
  end

  def create
    d = params.require(:stock_transfer)
    origin = current_branch.head_office? ? Branch.active.find(d[:origin_branch_id]) : current_branch
    destination = Branch.active.find(d[:destination_branch_id])
    stock_transfer = StockTransfer.register!(origin: origin, destination: destination, user: current_user, notes: d[:notes], key: d[:key],
                                   date: d[:date].presence || Date.current, lines: (d[:lines_attributes]&.to_unsafe_h || {}).values)
    redirect_to stock_transfer_path(stock_transfer), notice: t("stock_transfers.notices.registered", folio: stock_transfer.folio, destination: destination.name)
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, Inventory::OutOfStock => e
    redirect_to new_stock_transfer_path, alert: e.message
  end

  def show
    @stock_transfer = StockTransfer.includes(:origin_branch, :destination_branch, :user, lines: :product).find(params[:id])
  end

  def cancel
    stock_transfer = StockTransfer.find(params[:id])
    stock_transfer.cancel!(reason: params[:reason].to_s.strip, user: current_user)
    redirect_to stock_transfer_path(stock_transfer), notice: t("stock_transfers.notices.cancelled", folio: stock_transfer.folio)
  rescue ArgumentError, ActiveRecord::RecordInvalid, Inventory::OutOfStock => e
    redirect_to stock_transfer_path(stock_transfer), alert: e.message
  end
end
