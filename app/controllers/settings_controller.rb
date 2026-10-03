# Settings: one page with a sidebar and sections. "For you" (language, theme, density, text size) is
# per person; the rest (business and ticket, features, till) only for whoever manages users.
class SettingsController < ApplicationController
  tab :settings

  SECTIONS = %w[for_you business folios features till purchases].freeze

  def index
    @section = params[:section].presence_in(SECTIONS) || (params[:section] == "ticket" ? "business" : "for_you")
    authorize!("admin.users") unless @section == "for_you"
    @settings = Setting.to_h
    if @section == "business"
      @sale = sale_of_sample
      @preview = true
    end
  end

  def preferences
    current_user.update!(params.require(:user).permit(:language, :theme, :density, :text_size))
    redirect_to settings_path, notice: I18n.t("settings.saved", locale: current_user.language)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_path, alert: e.record.errors.full_messages.join(", ")
  end

  def save_ticket
    authorize!("admin.users")
    Setting.store!(params.fetch(:setting, {}).to_unsafe_h)
    redirect_to settings_section_path("business"), notice: t("settings.saved")
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to settings_section_path("business"), alert: e.message
  end

  def system
    authorize!("admin.users")
    Setting.store!(params.fetch(:setting, {}).to_unsafe_h)
    Features.store!(params[:features]) if params.key?(:features)
    redirect_to back, notice: t("settings.saved")
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to back, alert: e.message
  end

  private

  # Which section the system form returns to.
  def back
    settings_section_path(params[:back].presence_in(SECTIONS) || "features")
  end

  # A made-up sale, in memory, for the ticket preview.
  def sale_of_sample
    sale = Sale.new(branch: current_branch, user: current_user, folio: "B-00042", code: Barcode.ean13("090000000042"),
                  created_at: Time.current, total_cents: 21_450, change_cents: 3_550, status: "paid")
    [ [ t("settings.ticket.sample.product_kg"), "kg", "1.250", 12_900 ], [ t("settings.ticket.sample.product_piece"), "piece", "2", 2_650 ] ].each do |name, unit, qty, price|
      quantity = BigDecimal(qty)
      sale.lines.build(product: Product.new(name: name, unit: unit), quantity: quantity, price_cents: price,
                     catalog_cents: price, amount_cents: (quantity * price).round.to_i)
    end
    sale.payments.build(payment_method: "cash", amount_cents: 25_000)
    sale
  end
end
