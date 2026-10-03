# The Home dashboard editor: the Lisp program on the left and how it looks on the right.
# Trying saves nothing; saving records a new version only if the program runs; restoring
# records an old version again.
class DashboardController < ApplicationController
  include Dashboardable

  before_action { authorize!("rules.edit") }
  before_action :range

  def edit
    @code = Rule.current("dashboard")&.code.presence || Dashboard::DEFAULT
    preview(@code)
  end

  # "Try" and "Save" post to the same URL (the form token is bound to it); trying just carries
  # the dry_run=1 flag. From the modal it arrives via fetch and returns only the preview.
  def dry_run
    @code = params[:code].to_s
    preview(@code, sample: params[:sample] == "1")
    status = @program_error ? :unprocessable_entity : :ok
    return render(partial: "dashboard/preview", status: status) if request.xhr?
    render :edit, status: status
  end

  def save
    return dry_run if params[:dry_run].present?
    @code = params[:code].to_s
    preview(@code)
    return render(:edit, status: :unprocessable_entity) if @program_error
    Rule.create!(hook: "dashboard", code: @code, user: current_user)
    redirect_to root_path, notice: t("dashboard.notices.saved")
  rescue ActiveRecord::RecordInvalid => e
    @program_error = e.record.errors.full_messages.to_sentence
    render :edit, status: :unprocessable_entity
  end

  def restore
    old = Rule.for_hook("dashboard").find(params[:id])
    Rule.create!(hook: "dashboard", code: old.code, version: old.version, user: current_user)
    redirect_to dashboard_edit_path, notice: t("dashboard.notices.restored", date: l(old.created_at, format: :short))
  end

  private

  # Unlike Home, here the error is not hidden behind the default dashboard: it is shown.
  def preview(code, sample: false)
    build_dashboard(code: code, sample: sample)
    @program_error = @dashboard_error
    @versions = Rule.for_hook("dashboard").includes(:user).limit(15)
  end
end
