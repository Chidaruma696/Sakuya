# The hook for manual inventory movements (loose inflows, adjustments and waste): before moving
# stock, a rule in Sakuya's Lisp looks at what, how much and why, and decides. The core makes sure
# there is a reason and enough stock to take out.
#
# Contract v1. It gets (kind): :in, :adjust-in, :adjust-out or :waste; (quantity), (stock) what
# there is before moving it, (product) the product code, (value) what it is worth at catalog
# price, in money; plus (reason) the written reason and (authorized), true if whoever does it has
# inventory.adjust. Returns (allow), (to-review reason) or (reject reason).
module MovementRule
  VERSION = 1

  DEFAULT = <<~LISP
    ; Moving stock by hand: loose entries, adjustments and waste.
    ; Answer (allow), (to-review "why") or (reject "why").
    ; Without permission to adjust it stops and the attempt is reported.
    (if (authorized)
        (allow)
        (reject :needs-permission))
  LISP

  KINDS = { "inflow" => :in, "adjustment_inflow" => :"adjust-in", "adjustment_outflow" => :"adjust-out", "waste" => :waste }.freeze
  REASONS = %i[needs-permission].freeze
  FUNCTIONS = %w[kind quantity stock product value reason authorized].freeze
  EXAMPLE = <<~LISP
    (cond ((not (authorized)) (reject :needs-permission))
          ((and (= (kind) :waste) (> (value) 500)) (to-review "Big waste"))
          (else (allow)))
  LISP

  extend Hook

  SCENARIO = "rules/scenario_movement".freeze # the editor's test case

  Input = Data.define(:kind, :product, :quantity, :stock_level, :value, :reason, :authorized)

  def self.decide(branch:, product:, kind:, quantity:, reason:, user:, code: Rule.current("movement")&.code)
    decide_with(code, data(branch, product, kind, quantity, reason, user.can?("inventory.adjust")))
  end

  def self.data(branch, product, kind, quantity, reason, authorized)
    quantity = BigDecimal(quantity.to_s).round(3)
    Input.new(kind: kind, product: product, quantity: quantity, stock_level: StockLevel.find_by(branch: branch, product: product)&.quantity || BigDecimal("0"),
              value: Review.value(quantity, product, branch), reason: reason.to_s, authorized: authorized)
  end

  # The editor's test case: a product, which movement, how much, why and whether someone with
  # permission does it. The stock level and the value come from the branch.
  def self.scenario(params, branch)
    product = Product.active.find_by(key: params[:product].to_s.upcase) || Product.active.order(:name).first
    kind = params[:kind].presence_in(KINDS.keys) || "waste"
    quantity = (BigDecimal(params[:quantity].presence || "1") rescue BigDecimal("1"))
    { product: product, kind: kind, quantity: quantity, reason: params[:reason].presence || I18n.t("movement_rule.scenario.reason_example"),
      authorized: params[:authorized] == "1", branch: branch }
  end

  def self.dry_run(code, scenario)
    raise Lisp::Error, I18n.t("price_rule.no_products") unless scenario[:product]
    evaluate(code, data(scenario[:branch], scenario[:product], scenario[:kind], scenario[:quantity], scenario[:reason], scenario[:authorized]))
  end

  def self.texts = "movement_rule"

  def self.interpolate(_data) = {}

  def self.functions(data)
    {
      "kind" => -> { KINDS.fetch(data.kind) },
      "quantity" => -> { data.quantity },
      "stock" => -> { data.stock_level },
      "product" => -> { data.product.key },
      "value" => -> { BigDecimal(data.value) / 100 },
      "reason" => -> { data.reason },
      "authorized" => -> { data.authorized }
    }
  end

  private_class_method :functions, :interpolate, :texts, :data
end
