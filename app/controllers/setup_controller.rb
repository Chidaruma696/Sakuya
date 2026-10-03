# First-run setup screen: it only exists while there is no active user.
class SetupController < ApplicationController
  skip_before_action :require_setup, :require_session
  layout "session"

  FIELDS = %i[business business_type branch code name user password language theme density text_size folios_mode folios_prefix folios_sale].freeze

  def new
    return redirect_to root_path if User.active.exists?
    @data = { business_type: "all", code: "MTZ", user: "admin", language: I18n.locale.to_s, theme: "light", density: "normal", text_size: "normal", folios_mode: "per_document", folios_prefix: "own", folios_sale: "B" }
    @step = 1
  end

  def create
    return redirect_to root_path if User.active.exists?
    @data = params.require(:setup).permit(*FIELDS).to_h.symbolize_keys
    admin = Setup.install!(**FIELDS.index_with { |c| @data[c] })
    start_session(admin)
    redirect_to root_path, notice: I18n.t("setup.list", locale: admin.language)
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    flash.now[:alert] = e.respond_to?(:record) ? e.record.errors.full_messages.join(", ") : e.message
    @step = 6
    render :new, status: :unprocessable_entity
  end
end
