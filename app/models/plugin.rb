# A Lisp plugin: a file the business installs to bring what Sakuya does not bring out of the box.
# It only declares; installing it reads it, it never runs. It can bring:
#
#   (plugin "fonda" (name "Fonda") (version "1.0") (author "…") (description "…"))
#   (define (fonda/margin sales returns) (- sales returns))   ; functions for every rule
#   (report "Sales of the week" (sales (days-ago 7) (today))) ; reports for the REPL
#   (translation "fr" "Français" ("till.checkout" "Encaisser")) ; a language for the interface
#
# Functions carry the plugin prefix ("fonda/…"), so they do not clash with Sakuya's or with
# another plugin's. A switched-off plugin contributes nothing.
class Plugin < ApplicationRecord
  self.table_name = "plugins"
  IDENTIFIER = /\A[a-z][a-z0-9-]{1,30}\z/
  LANGUAGE = /\A[a-z]{2}(-[A-Z]{2})?\z/
  DATA = %w[name version author description].freeze
  EXAMPLE = <<~LISP
    ; fonda.lisp: a Sakuya plugin. It only declares; nothing runs when it is installed.
    (plugin "fonda"
      (name "Fonda")
      (version "1.0")
      (author "Someone")
      (description "Helpers for a small eatery"))

    ; Functions for every rule, the dashboard and the REPL. They carry the plugin prefix.
    (define (fonda/big-discount? limit) (> (discount) limit))

    ; Saved questions for the REPL.
    (report "Sales of the week" (sum-of :total (sales (days-ago 7) (today))))

    ; A language for the interface; whatever it does not translate stays in English.
    (translation "fr" "Français"
      ("till.checkout" "Encaisser")
      ("ribbon.tabs.till" "Caisse"))
  LISP
  EXAMPLE.freeze

  belongs_to :user

  validates :identifier, presence: true, uniqueness: true, format: { with: IDENTIFIER }
  validates :name, :code, presence: true

  scope :active, -> { where(active: true).order(:identifier) }

  Parsed = Data.define(:identifier, :data, :functions, :reports, :translations)
  Report = Data.define(:plugin, :title, :code)
  Translation = Data.define(:language, :name, :texts)

  # Reads a plugin file and checks everything it brings; raises Lisp::Error with whatever fails.
  def self.read(text)
    forms = Lisp::Reader.read(text.to_s)
    head = forms.first
    unless head.is_a?(Array) && head.first == Lisp::Sym.new("plugin") && head[1].is_a?(String)
      raise Lisp::Error, I18n.t("plugins.errors.header")
    end
    id = head[1]
    raise Lisp::Error, I18n.t("plugins.errors.identifier", id: id) unless id.match?(IDENTIFIER)
    data = head.drop(2).to_h do |pair|
      unless pair.is_a?(Array) && pair.size == 2 && pair.first.is_a?(Lisp::Sym) && DATA.include?(pair.first.name) && pair.last.is_a?(String)
        raise Lisp::Error, I18n.t("plugins.errors.datum", datum: Lisp.to_text(pair), data: DATA.join(", "))
      end
      [ pair.first.name, pair.last ]
    end
    functions = []
    reports = []
    translations = []
    forms.drop(1).each do |form|
      case form.is_a?(Array) && form.first.is_a?(Lisp::Sym) ? form.first.name : nil
      when "define" then functions << review_define!(form, id)
      when "report" then reports << review_report!(form, id)
      when "translation" then translations << review_translation!(form)
      else raise Lisp::Error, I18n.t("plugins.errors.form", form: Lisp.to_text(form).truncate(60))
      end
    end
    Parsed.new(identifier: id, data: data, functions: functions, reports: reports, translations: translations)
  end

  # Only (define (prefix/name args…) body…) or (define prefix/name value).
  def self.review_define!(form, id)
    destination = form[1]
    name = (destination.is_a?(Array) ? destination.first : destination)
    unless name.is_a?(Lisp::Sym) && name.name.start_with?("#{id}/") && form.size >= 3
      raise Lisp::Error, I18n.t("plugins.errors.prefix", name: Lisp.to_text(name), id: id)
    end
    form
  end

  def self.review_report!(form, id)
    unless form.size == 3 && form[1].is_a?(String)
      raise Lisp::Error, I18n.t("plugins.errors.report")
    end
    Report.new(plugin: id, title: form[1], code: Lisp.to_text(form[2]))
  end

  def self.review_translation!(form)
    language, name, *pairs = form.drop(1)
    unless language.is_a?(String) && language.match?(LANGUAGE) && name.is_a?(String)
      raise Lisp::Error, I18n.t("plugins.errors.translation")
    end
    texts = pairs.to_h do |pair|
      raise Lisp::Error, I18n.t("plugins.errors.pair", pair: Lisp.to_text(pair).truncate(60)) unless pair.is_a?(Array) && pair.size == 2 && pair.all?(String)
      pair
    end
    # *_html keys are rendered unescaped: a plugin does not touch them.
    html = texts.keys.select { |key| key.end_with?("_html") || key.split(".").last == "html" }
    raise Lisp::Error, I18n.t("plugins.errors.html", keys: html.first(5).join(", ")) if html.any?
    unknown = texts.keys.reject { |key| I18n.exists?(key, locale: :en) }
    raise Lisp::Error, I18n.t("plugins.errors.keys", keys: unknown.first(5).join(", ")) if unknown.any?
    Translation.new(language: language, name: name, texts: texts)
  end

  private_class_method :review_define!, :review_report!, :review_translation!

  # Installs (or updates, if it was already there) a plugin from its file. A new one arrives switched off.
  def self.install!(text, user:)
    parsed = read(text)
    plugin = find_or_initialize_by(identifier: parsed.identifier)
    plugin.update!(name: parsed.data["name"].presence || parsed.identifier, version: parsed.data["version"], author: parsed.data["author"],
                   description: parsed.data["description"], code: text, user: user)
    plugin
  end

  def parsed = @parsed ||= self.class.read(code)

  # The active plugins' functions, already read, to evaluate before each program. Cached by the
  # time of the last change to any plugin.
  def self.prelude
    key = pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(updated_at)"))
    @prelude = nil if @prelude_key != key
    @prelude_key = key
    @prelude ||= active.flat_map { |p| p.parsed.functions }.freeze
  end

  def self.reports = active.flat_map { |p| p.parsed.reports }

  def to_s = name
end
