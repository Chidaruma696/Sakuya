# Features switched on or off per business (the full map is in docs/arquitectura.md). Till,
# inventory, admin and settings are always on; the rest depends on the business type chosen at
# setup and can be changed later in Settings. Each feature is a separate set: its tables, its
# permissions, its tab. DEPENDS and ANY are ready for when one feature hangs off another.
module Features
  OPTIONAL = %w[purchases warehouses stock_counts customers].freeze
  DEPENDS = {}.freeze
  # Needs at least one from the list switched on.
  ANY = {}.freeze
  # Permission prefixes that hang off each feature (the other permissions are always there).
  PERMISSIONS = { "purchases" => %w[purchases], "warehouses" => %w[warehouses], "stock_counts" => %w[stock_counts], "customers" => %w[customers] }.freeze
  # Preset per business type.
  BUSINESS_TYPES = {
    "store" => %w[purchases stock_counts],
    "several_branches" => %w[purchases warehouses stock_counts],
    "all" => OPTIONAL
  }.freeze

  def self.active?(key)
    return true unless OPTIONAL.include?(key.to_s)
    active.include?(key.to_s)
  end

  # Read once per request (Current) so the table is not queried for every ribbon button.
  def self.active
    Current.features ||= OPTIONAL.select { |m| Setting["features.#{m}"] == "1" }
  end

  def self.permission_active?(key)
    prefix = key.to_s.split(".").first
    feature = PERMISSIONS.find { |_, prefixes| prefixes.include?(prefix) }&.first
    feature.nil? || active?(feature)
  end

  # At setup there is no open work to protect.
  def self.apply_business_type!(business_type)
    store!(BUSINESS_TYPES.fetch(business_type.to_s, OPTIONAL), check: false)
  end

  # What a feature needs switched on, and which ones need it.
  def self.needs(feature) = DEPENDS.fetch(feature.to_s, [])
  def self.any(feature) = ANY.fetch(feature.to_s, [])
  def self.dependents(feature) = DEPENDS.select { |_, base| base.include?(feature.to_s) }.keys
  # Which ones would have `feature` as their last base switched on within `active`.
  def self.dependents_any(feature, active)
    ANY.select { |d, options| active.include?(d) && options.include?(feature.to_s) && (options & active).empty? }.keys
  end

  def self.name(feature) = I18n.t("features.#{feature}.name")

  # Switches on the ones in the list and switches off the rest. Switching one on pulls in what it
  # needs; switching off a base another active one needs is rejected naming it, and so is switching
  # off something with open work.
  def self.store!(list, check: true)
    added = (Array(list).map(&:to_s) & OPTIONAL)
    old = active
    (added - old).each do |m|
      added |= needs(m)
      added |= [ any(m).first ] if any(m).any? && (any(m) & added).empty?
    end
    (old - added).each do |m|
      who = (dependents(m) & added) | dependents_any(m, added)
      raise ArgumentError, I18n.t("errors.feature.with_dependents", feature: name(m), dependents: who.map { |d| name(d) }.join(", ")) if who.any?
      check_switchable!(m) if check
    end
    Setting.store!(OPTIONAL.to_h { |m| [ "features.#{m}", added.include?(m) ? "1" : "0" ] })
    Current.features = nil
  end

  def self.check_switchable!(feature)
    open = case feature
    when "stock_counts" then StockCount.still_open.exists?
    when "warehouses" then Branch.active.warehouses.exists?
    end
    raise ArgumentError, I18n.t("errors.feature.with_work_open", feature: I18n.t("features.#{feature}.name")) if open
  end
end
