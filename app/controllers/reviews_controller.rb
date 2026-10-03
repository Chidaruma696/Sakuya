# The deferred authorization inbox: what was done without anyone authorizing it at the time.
# The supervisor sees it all together at the end of the day and decides: approve, or flag (and charge).
class ReviewsController < ApplicationController
  tab :home

  before_action { authorize!("reviews.resolve") }

  def index
    @all = current_branch.head_office? && params[:branch_id] == "all"
    scope = @all ? Review.all : Review.where(branch: current_branch)
    @pending = scope.pending.includes(:user, :branch, :reviewable).order(:created_at)
    @resolved = scope.resolved.includes(:user, :branch, :reviewed_by, :charge).order(reviewed_at: :desc).limit(30)
  end

  def resolve
    review = Review.find(params[:id])
    raise NotAllowed, "reviews.resolve" unless review.branch_id == current_branch.id || current_branch.head_office?
    if params[:status] == "flagged"
      review.flag!(user: current_user, note: params[:note].presence, charge_cents: Money.cents(params[:charge]))
      notice = review.charge ? t("reviews.flagged_loaded", who: review.user, amount: Money.format_money(review.charge.amount_cents)) : t("reviews.flagged_no_charge")
    else
      review.approve!(user: current_user, note: params[:note].presence)
      notice = t("reviews.approved")
    end
    redirect_to reviews_path(branch_id: params[:branch_id]), notice: notice
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to reviews_path(branch_id: params[:branch_id]), alert: e.message
  end
end
