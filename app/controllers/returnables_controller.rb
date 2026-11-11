# Returnable containers outside a sale, from the customer's account: pieces that come back loose,
# pieces written off and loose entries. Each has its own permission; what they record goes
# through Returnables.
class ReturnablesController < ApplicationController
  tab :customers
  feature :customers, :returnables

  before_action { @customer = Customer.find(params[:customer_id]) }

  # Up to what the customer owes, nobody is asked. More than that comes back to the account screen
  # with the dialog: only someone with returnables.in_favor can accept the surplus there.
  def receive
    authorize!("returnables.receive")
    Returnables.receive!(customer: @customer, kind: params[:kind], quantity: params[:quantity], user: current_user, branch: current_branch,
                         accept_in_favor: params[:accept_in_favor] == "1", key: params[:key])
    back t("returnables.notices.received", pieces: params[:quantity].to_i, kind: Returnables.name(params[:kind]))
  rescue Returnables::MoreThanOwed
    redirect_to account_customer_path(@customer, over_kind: params[:kind], over_quantity: params[:quantity].to_i, anchor: "returnables")
  end

  def write_off
    authorize!("returnables.write_off")
    Returnables.write_off!(customer: @customer, kind: params[:kind], quantity: params[:quantity], reason: params[:reason].to_s.strip, user: current_user,
                           branch: current_branch, key: params[:key])
    back t("returnables.notices.written_off", pieces: params[:quantity].to_i, kind: Returnables.name(params[:kind])) + t("till.notices.remains_pending_review")
  end

  def entry
    authorize!("returnables.adjust")
    Returnables.enter!(customer: @customer, kind: params[:kind], quantity: params[:quantity], direction: params[:direction].to_s, note: params[:note].to_s.strip,
                       user: current_user, branch: current_branch, key: params[:key])
    back t("returnables.notices.entered", pieces: params[:quantity].to_i, kind: Returnables.name(params[:kind])) + t("till.notices.remains_pending_review")
  end

  private

  rescue_from Returnables::Error, ActiveRecord::RecordInvalid do |e|
    redirect_to account_customer_path(@customer, anchor: "returnables"), alert: e.message
  end

  def back(notice) = redirect_to(account_customer_path(@customer, anchor: "returnables"), notice: notice)
end
