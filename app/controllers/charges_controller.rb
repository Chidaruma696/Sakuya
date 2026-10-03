class ChargesController < ApplicationController
  tab :stock_counts
  feature :stock_counts

  before_action { authorize!("stock_counts.charges") }

  def index
    @charges = Charge.where(branch: current_branch).includes(:user, :stock_count, :review, :resolved_by).order(created_at: :desc).limit(100)
  end

  def resolve
    charge = Charge.where(branch: current_branch).find(params[:id])
    charge.resolve!(params[:status].presence_in(%w[paid forgiven]) || "paid", user: current_user)
    redirect_to charges_path, notice: t("charges.notices.marked", who: charge.user, status: t("statuses.#{charge.status}"))
  rescue ArgumentError => e
    redirect_to charges_path, alert: e.message
  end
end
