# The order and look of the sale ticket's blocks, arranged with the mouse in Settings › Business
# and ticket. A thermal printer prints line by line, so the ticket is a stack of blocks: each one
# can move up or down, and some can be aligned, enlarged, set in bold, underlined or hidden. Saved as JSON in the
# `ticket.layout` setting; blank is the built-in layout, the ticket as it always was.
#
#   [{"k":"name","a":"left","l":true,"b":true},{"k":"tagline","b":false,"u":true,"off":true},…]
module TicketLayout
  Block = Data.define(:key, :align, :large, :bold, :underline, :off) do
    def can?(what) = BLOCKS.fetch(key).last.include?(what)
    def css = [ "block", ("a-#{align}" if align), ("large" if large), ("bold" if bold), ("underline" if underline), ("off" if off) ].compact.join(" ")
  end

  ALIGNS = %w[left center right].freeze
  BOLD = %w[name phone].freeze # in bold unless the designer says otherwise
  # In the built-in order. key => [built-in alignment, what the designer may change]. A block whose
  # size can change can also be set in bold or underlined.
  BLOCKS = {
    "logo" => [ "center", %w[align] ],
    "name" => [ "center", %w[align size] ],
    "tagline" => [ "center", %w[align size hide] ],
    "branch" => [ "center", %w[align size hide] ],
    "address" => [ "center", %w[align size hide] ],
    "phone" => [ "center", %w[align size hide] ],
    "tax_id" => [ "center", %w[align size hide] ],
    "info" => [ nil, [] ],
    "lines" => [ nil, [] ],
    "totals" => [ nil, [] ],
    "returns_legend" => [ "center", %w[align size hide] ],
    "barcode" => [ nil, [] ],
    "footer" => [ "center", %w[align size hide] ]
  }.freeze

  # The fixed words on the ticket that a business may want in its own (double click on the
  # preview): key => the translation used when nothing was typed. Saved as JSON in `ticket.labels`,
  # only the ones that were changed; a typed word is used as is in every language.
  LABELS = { "date" => "common.date", "folio" => "common.folio", "served_by" => "till.served_by", "product" => "common.product",
             "quantity" => "common.quantity", "price" => "common.price", "line_amount" => "common.line_amount",
             "total" => "common.total", "change" => "till.change" }.freeze
  MAX_LABEL = 40

  def self.default_label(key) = I18n.t(LABELS.fetch(key)).then { |text| key == "total" ? text.upcase : text }

  # Every label with the word to print: the business's if it typed one, the translation if not.
  def self.labels
    custom = parse_labels(Setting["ticket.labels"])
    LABELS.keys.index_with { |key| custom[key] || default_label(key) }
  end

  def self.parse_labels(json)
    typed = json.present? ? JSON.parse(json) : {}
    return {} unless typed.is_a?(Hash)
    typed.slice(*LABELS.keys).transform_values { |text| text.to_s.squish.first(MAX_LABEL) }.compact_blank
  rescue JSON::ParserError
    {}
  end

  # What gets saved: only the labels that differ from the translation, or blank if none does.
  def self.normalize_labels!(value)
    return "" if value.blank?
    raise ArgumentError, I18n.t("errors.setting.layout") unless JSON.parse(value).is_a?(Hash)
    typed = parse_labels(value).reject { |key, text| text == default_label(key) }
    typed.empty? ? "" : typed.to_json
  rescue JSON::ParserError
    raise ArgumentError, I18n.t("errors.setting.layout")
  end

  def self.default = BLOCKS.map { |key, (align, _)| Block.new(key: key, align: align, large: false, bold: BOLD.include?(key), underline: false, off: false) }

  def self.current = parse(Setting["ticket.layout"])

  # Whatever comes in, a complete layout comes out: unknown blocks are dropped, missing ones go
  # at the end in the built-in order, and a block only keeps what it is allowed to change.
  def self.parse(json)
    list = json.present? ? JSON.parse(json) : []
    list = [] unless list.is_a?(Array)
    seen = list.filter_map do |item|
      next unless item.is_a?(Hash) && BLOCKS.key?(item["k"])
      align, can = BLOCKS.fetch(item["k"])
      Block.new(key: item["k"], align: can.include?("align") && ALIGNS.include?(item["a"]) ? item["a"] : align,
                large: can.include?("size") && item["l"] == true,
                bold: can.include?("size") && [ true, false ].include?(item["b"]) ? item["b"] : BOLD.include?(item["k"]),
                underline: can.include?("size") && item["u"] == true, off: can.include?("hide") && item["off"] == true)
    end.uniq(&:key)
    seen + default.reject { |block| seen.any? { |s| s.key == block.key } }
  rescue JSON::ParserError
    default
  end

  def self.dump(blocks)
    blocks.map { |b| { "k" => b.key, "a" => b.align, "l" => b.large || nil, "b" => (b.bold if b.can?("size")), "u" => b.underline || nil, "off" => b.off || nil }.compact }.to_json
  end

  # What gets saved: the layout cleaned up, or blank if it is the built-in one.
  def self.normalize!(value)
    return "" if value.blank?
    raise ArgumentError, I18n.t("errors.setting.layout") unless JSON.parse(value).is_a?(Array)
    blocks = parse(value)
    blocks == default ? "" : dump(blocks)
  rescue JSON::ParserError
    raise ArgumentError, I18n.t("errors.setting.layout")
  end
end
