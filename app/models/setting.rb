# System settings, key/value, with their defaults. Anything not saved takes the default;
# `Setting[key]` always returns something.
class Setting < ApplicationRecord
  # Keys where blank is saved as is instead of going back to the default.
  NO_PREFIX = Folio::DOCUMENTS.keys.map { |d| "folios.#{d}" }.push("folios.single").freeze

  DEFAULTS = {
    "business.name" => "",              # blank = the branch name
    "business.address" => "",
    "business.phone" => "",
    "business.ticket_footer" => -> { I18n.t("settings.defaults.ticket_footer") },
    "business.currency" => "MXN",           # ISO code, shown in reports and exports
    "business.symbol" => "$",            # what goes right before the figure: $, €, Q, S/…
    "ticket.logo" => "",                 # image as a data URL (small PNG/JPG), at the top of the ticket
    "ticket.tagline" => "",                 # line under the name
    "ticket.tax_id" => "",                  # tax ID
    "ticket.returns_legend" => "", # blank = the system text
    "ticket.show_cashier" => "1",
    "ticket.show_code" => "1",      # the ticket's barcode
    "ticket.width" => "80",              # paper width in mm: 80 or 58
    "till.price_floor" => "50",          # % of the catalog price below which nothing sells, not even with permission
    "till.drawer_limit" => "3000",      # money, for new branches
    "till.denominations" => "1000,500,200,100,50,20,10,5,2,1,0.5", # bills and coins for counting the drawer
    "till.difference_cap" => "0",       # money; if |counted − expected| goes over it, closing asks for a reason. 0 = no cap
    "purchases.lock_received" => "1", # "1" = invoicing more than was received is stopped (on by default)
    "folios.mode" => "per_document",   # or "single": one running sequence for everything
    "folios.single" => "F",
    "folios.branch" => "0",            # "1" = the branch code goes in front of the folio
    **Folio::DOCUMENTS.to_h { |doc, prefix| [ "folios.#{doc}", prefix ] },
    "features.purchases" => "1",           # optional features: "1" on, "0" off (see Features)
    "features.warehouses" => "1",
    "features.stock_counts" => "1",
    "features.customers" => "0"           # off by default: switched on in Settings › Features
  }.freeze
  INTEGERS = %w[till.price_floor till.drawer_limit till.difference_cap ticket.width].freeze
  DENOMINATIONS = /\A\d+(\.\d{1,2})?(,\d+(\.\d{1,2})?)*\z/
  LOGO_MAX = 400_000 # data URL characters (~300 KB of image)

  validates :key, presence: true, uniqueness: true, inclusion: { in: DEFAULTS.keys }

  # The currency symbol, one query per request.
  def self.symbol = (Current.symbol ||= self["business.symbol"])

  # The ticket's printable width in mm according to the paper (80 → 72, 58 → 48).
  def self.ticket_width_mm = integer("ticket.width") == 58 ? 48 : 72

  def self.[](key)
    value = find_by(key: key)&.value
    # A blank folio prefix is a legitimate value (just the number); everywhere else, blank = default.
    return value if !value.nil? && NO_PREFIX.include?(key)
    value.presence || DEFAULTS.fetch(key).then { |d| d.respond_to?(:call) ? d.call : d }
  end

  def self.integer(key)
    self[key].to_i
  end

  # Saves several at once: { "business.name" => "…" }. Blank goes back to the default.
  def self.store!(values)
    transaction do
      values.each do |key, value|
        next unless DEFAULTS.key?(key)
        value = value.to_s.strip
        raise ArgumentError, I18n.t("errors.setting.integer", key: key) if INTEGERS.include?(key) && value.present? && value !~ /\A\d+\z/
        raise ArgumentError, I18n.t("errors.setting.prefix", key: key) if key.start_with?("folios.") && !%w[folios.mode folios.branch].include?(key) && (value = value.upcase) !~ Folio::PREFIX
        raise ArgumentError, I18n.t("errors.setting.mode_folios") if key == "folios.mode" && value.present? && !Folio::MODES.include?(value)
        raise ArgumentError, I18n.t("errors.setting.denominations") if key == "till.denominations" && value.present? && (value = value.delete(" ")) !~ DENOMINATIONS
        raise ArgumentError, I18n.t("errors.setting.logo") if key == "ticket.logo" && value.present? && (value.length > LOGO_MAX || value !~ %r{\Adata:image/(png|jpeg|gif|webp);base64,})
        record = find_or_initialize_by(key: key)
        value.blank? && !NO_PREFIX.include?(key) ? record.destroy : record.update!(value: value)
      end
    end
    Current.symbol = nil
  end

  def self.to_h
    DEFAULTS.keys.index_with { |k| self[k] }
  end
end
