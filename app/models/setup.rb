# First run: with an empty database, creates the base roles, the head office, the business name and
# the administrator, all in one transaction. Returns the newly created administrator.
module Setup
  # folios_mode: per_document | single. folios_prefix: branch (the branch code goes in front),
  # own (whatever letters are typed in folios_sale, for till receipts) or none (just the number).
  def self.install!(business:, business_type:, branch:, code:, name:, user:, password:, language:, theme: nil, density: nil, text_size: nil,
                     folios_mode: nil, folios_prefix: nil, folios_sale: nil)
    ActiveRecord::Base.transaction do
      Role.base!
      Features.apply_business_type!(business_type)
      head_office = Branch.find_or_create_by!(code: code.to_s.strip.upcase.presence || "MTZ") do |b|
        b.name = branch.to_s.strip.presence || business.to_s.strip.presence || I18n.t("setup.head_office_name")
        b.kind = "head_office"
      end
      Setting.store!("business.name" => business) if business.present?
      Setting.store!(folio_settings(folios_mode, folios_prefix, folios_sale))
      User.create!(name: name, user: user.to_s.strip.downcase, password: password,
                      role: Role.find_by!(name: "administrator"), branch: head_office,
                      language: language.to_s.presence_in(User::LANGUAGES) || "en",
                      theme: theme.to_s.presence_in(User::THEMES) || "light",
                      density: density.to_s.presence_in(User::DENSITIES) || "normal",
                      text_size: text_size.to_s.presence_in(User::TEXT_SIZES) || "normal")
    end
  end

  def self.folio_settings(mode, prefix, sale)
    mode = mode.to_s.presence_in(Folio::MODES) || "per_document"
    settings = { "folios.mode" => mode, "folios.branch" => (prefix.to_s == "branch" ? "1" : "0") }
    case prefix.to_s
    when "branch" then settings["folios.single"] = ""                    # MTZ-00001 with a single sequence, MTZ-B-00001 per document
    when "own"
      settings["folios.sale"] = sale.to_s.strip.upcase
      settings["folios.single"] = sale.to_s.strip.upcase if mode == "single"
    when "none" then Setting::NO_PREFIX.each { |k| settings[k] = "" }
    end
    settings
  end
end
