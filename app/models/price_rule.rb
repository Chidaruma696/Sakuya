# The price hook: every line being checked out goes through a rule in Sakuya's Lisp that looks at
# the price the till set and decides. Nobody crosses the floor from Settings › Till, not even with
# a rule; everything else is up to the rule.
#
# Contract v1. It gets, in money: (price) what is being charged, (list-price) the branch's catalog
# price, (regular-price) what applies (the best promotion or the catalog price), (discount) how
# many percent below what applies (0 if there is no markdown); plus (quantity), (product) the
# product code and (authorized), true if whoever authorizes has till.lower_price. Returns (allow),
# (to-review reason) or (reject reason).
module PriceRule
  VERSION = 1

  DEFAULT = <<~LISP
    ; Each line at the till. (price) is what is being charged; (regular-price) is the list price or the promotion.
    ; Answer (allow), (to-review "why") or (reject "why").
    ; Below the regular price it stops: only someone allowed to lower prices can sell it, and it goes to review.
    (if (>= (price) (regular-price))
        (allow)
        (reject :below-price))
  LISP

  REASONS = %i[below-price].freeze

  extend Hook

  SCENARIO = "rules/scenario_price".freeze # the editor's test case

  Input = Data.define(:product, :quantity, :price, :catalog, :regular, :authorized) do
    def money(cents) = BigDecimal(cents.to_i) / 100
    def discount = regular.positive? && price < regular ? ((regular - price) * 100 / BigDecimal(regular)).round(2) : BigDecimal("0")
  end

  def self.decide(data, code:)
    decide_with(code, data)
  end

  # The editor's test case: a catalog product, how much is bought, at what price and whether
  # someone with permission checks it out. What applies comes from the branch's catalog and promotions.
  def self.scenario(params, branch)
    product = Product.active.find_by(key: params[:product].to_s.upcase) || Product.active.order(:name).find { |p| p.price_cents_for(branch).positive? }
    quantity = BigDecimal(params[:quantity].presence || "1") rescue BigDecimal("1")
    catalog = product ? product.price_cents_for(branch) : 0
    regular = product ? (Promotion.best(product, branch, quantity, catalog)&.first || catalog) : 0
    price = params[:price].present? ? Money.cents(params[:price]) : regular
    sale = Sale.where(branch: branch).find_by(folio: params[:sale].to_s.strip.upcase) if params[:sale].present?
    { product: product, quantity: quantity, price: price, catalog: catalog, regular: regular, authorized: params[:authorized] == "1",
      sale: sale, sale_folio: params[:sale].to_s.strip.upcase.presence, branch: branch }
  end

  # With a real sale, goes over its lines as they were checked out (what applied is recalculated
  # with the catalog price back then and today's promotions) and returns one decision per line.
  def self.dry_run(code, scenario)
    raise Lisp::Error, I18n.t("price_rule.sale_not_found", folio: scenario[:sale_folio]) if scenario[:sale_folio] && !scenario[:sale]
    return dry_run_sale(code, scenario) if scenario[:sale]
    raise Lisp::Error, I18n.t("price_rule.no_products") unless scenario[:product]
    evaluate(code, Input.new(product: scenario[:product], quantity: scenario[:quantity], price: scenario[:price], catalog: scenario[:catalog], regular: scenario[:regular], authorized: scenario[:authorized]))
  end

  def self.dry_run_sale(code, scenario)
    scenario[:sale].lines.includes(:product, :authorized_by).map do |l|
      regular = Promotion.best(l.product, scenario[:branch], l.quantity, l.catalog_cents)&.first || l.catalog_cents
      data = Input.new(product: l.product, quantity: l.quantity, price: l.price_cents, catalog: l.catalog_cents, regular: regular,
                        authorized: scenario[:authorized] || l.authorized_by.present?)
      [ I18n.t("till.price_line", product: "#{l.product.name} × #{l.quantity.to_s("F")}", price: Money.format_money(l.price_cents), regular: Money.format_money(regular)), evaluate(code, data), data.authorized ]
    end
  end

  FUNCTIONS = %w[price list-price regular-price discount quantity product authorized].freeze
  EXAMPLE = <<~LISP
    (cond ((= (discount) 0) (allow))
          ((= (product) "CATS") (reject "Never discounted"))
          ((<= (discount) 5) (allow))
          (else (to-review "Big discount")))
  LISP

  def self.texts = "price_rule"

  def self.interpolate(data)
    { product: data.product.name, price: Money.format_money(data.price), regular: Money.format_money(data.regular) }
  end

  def self.functions(data)
    {
      "price" => -> { data.money(data.price) },
      "list-price" => -> { data.money(data.catalog) },
      "regular-price" => -> { data.money(data.regular) },
      "discount" => -> { data.discount },
      "quantity" => -> { data.quantity },
      "product" => -> { data.product.key },
      "authorized" => -> { data.authorized }
    }
  end

  private_class_method :functions, :interpolate, :texts, :dry_run_sale
end
