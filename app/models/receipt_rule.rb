# The hook for receiving goods from a supplier: before they enter the inventory, a rule in Sakuya's
# Lisp looks at what arrives, from whom and with what paperwork, and decides.
#
# Contract v1. It gets (supplier) the supplier's name, (lines) how many lines, (products) the list
# of product codes, (quantity-of "CODE") how much of that product arrives, (value) what it is worth
# at catalog price, in money, (delivery-note) the delivery note as typed ("" if there is none),
# (invoiced) whether it is linked to an invoice and (authorized), true if whoever receives it has
# purchases.force_receipt. Returns (allow), (to-review reason) or (reject reason).
module ReceiptRule
  VERSION = 1

  DEFAULT = <<~LISP
    ; Goods arriving from a supplier, right before they enter the stock.
    ; Answer (allow), (to-review "why") or (reject "why").
    ; Out of the box nothing stops a receipt.
    (allow)
  LISP

  REASONS = %i[].freeze
  FUNCTIONS = %w[supplier lines products quantity-of value delivery-note invoiced authorized].freeze
  EXAMPLE = <<~LISP
    (cond ((= (delivery-note) "") (reject "No delivery note, no goods"))
          ((> (value) 50000) (to-review "Big delivery"))
          (else (allow)))
  LISP

  extend Hook

  SCENARIO = "rules/scenario_receipt".freeze # the editor's test case

  # rows: [{ product:, quantity: }]
  Input = Data.define(:supplier, :rows, :value, :delivery_note, :invoiced, :authorized)

  def self.decide(data, code: Rule.current("receipt")&.code)
    decide_with(code, data)
  end

  # lines as they come from the form: [{ product_id:, quantity: }]
  def self.data(branch:, supplier:, lines:, delivery_note:, invoiced:, authorized:)
    rows = lines.map { |l| l.to_h.symbolize_keys }.reject { |l| l[:product_id].blank? || BigDecimal(l[:quantity].to_s.presence || "0") <= 0 }
                      .map { |l| { product: Product.active.find(l[:product_id]), quantity: BigDecimal(l[:quantity].to_s) } }
    value = rows.sum { |r| Review.value(r[:quantity], r[:product], branch) }
    Input.new(supplier: supplier.name, rows: rows, value: value, delivery_note: delivery_note.to_s.strip, invoiced: invoiced, authorized: authorized)
  end

  # The editor's test case: product codes with quantities ("CATS 10, PECH 2.5"), delivery note and
  # whether it comes with an invoice. The value comes from the branch's catalog.
  def self.scenario(params, branch)
    text = params[:arriving].presence || Product.active.order(:name).limit(2).pluck(:key).map { |k| "#{k} 10" }.join(", ")
    { arriving: text, delivery_note: params.key?(:delivery_note) ? params[:delivery_note].to_s : "R-123", invoiced: params[:invoiced] == "1",
      authorized: params[:authorized] == "1", branch: branch }
  end

  def self.dry_run(code, scenario)
    lines = scenario[:arriving].split(",").map(&:split).reject(&:empty?).map do |key, quantity|
      product = Product.active.find_by(key: key.upcase) or raise Lisp::Error, I18n.t("dashboard.errors.product", key: key.upcase)
      { product_id: product.id, quantity: quantity.presence || "1" }
    end
    evaluate(code, data(branch: scenario[:branch], supplier: Supplier.new(name: ""), lines: lines, delivery_note: scenario[:delivery_note], invoiced: scenario[:invoiced], authorized: scenario[:authorized]))
  end

  def self.texts = "receipt_rule"

  def self.interpolate(_data) = {}

  def self.functions(data)
    {
      "supplier" => -> { data.supplier },
      "lines" => -> { data.rows.size },
      "products" => -> { data.rows.map { |r| r[:product].key }.uniq },
      "quantity-of" => ->(key) { data.rows.select { |r| r[:product].key == key.to_s.upcase }.sum(BigDecimal("0")) { |r| r[:quantity] } },
      "value" => -> { BigDecimal(data.value) / 100 },
      "delivery-note" => -> { data.delivery_note },
      "invoiced" => -> { data.invoiced },
      "authorized" => -> { data.authorized }
    }
  end

  private_class_method :functions, :interpolate, :texts
end
