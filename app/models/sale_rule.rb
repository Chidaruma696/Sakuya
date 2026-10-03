# The hook for closing a sale: with the whole ticket (and every price already judged by the price
# rule), a rule in Sakuya's Lisp looks at the entire sale before checking it out, and decides.
#
# Contract v1. It gets, in money: (total), (change), (paid-with :cash|:transfer|:deposit) what
# was paid that way; plus (lines) how many lines, (products) the list of product codes,
# (quantity-of "CODE") how much of that product is bought, (hour) the hour (0-23), (weekday) the
# day (1 Monday … 7 Sunday) and (authorized), true if whoever checks out has till.force_sale.
# Returns (allow), (to-review reason) or (reject reason).
module SaleRule
  VERSION = 1

  DEFAULT = <<~LISP
    ; The whole ticket, right before charging it. Each price was already judged by the price rule.
    ; Answer (allow), (to-review "why") or (reject "why").
    ; Out of the box nothing else stops a sale.
    (allow)
  LISP

  PAYMENT_METHODS = { cash: "cash", transfer: "transfer", deposit: "deposit", credit: "credit" }.freeze
  REASONS = %i[].freeze
  FUNCTIONS = %w[total change paid-with lines products quantity-of hour weekday authorized].freeze
  EXAMPLE = <<~LISP
    (cond ((and (> (quantity-of "BEER") 0) (>= (hour) 22)) (reject "No beer after 10 pm"))
          ((> (total) 20000) (to-review "Big sale"))
          (else (allow)))
  LISP

  extend Hook

  SCENARIO = "rules/scenario_sale".freeze # the editor's test case

  # rows: [{ key:, quantity: }]; payments: { "cash" => cents, … }
  Input = Data.define(:total, :change, :rows, :payments, :moment, :authorized)

  def self.decide(data, code:)
    decide_with(code, data)
  end

  def self.data(lines, payments, total:, change:, authorized:, moment: Time.current)
    Input.new(total: total, change: change, rows: lines.map { |l| { key: l[:product].key, quantity: l[:quantity] } },
              payments: payments.group_by { |p| p[:payment_method] }.transform_values { |ps| ps.sum { |p| p[:amount_cents] } }, moment: moment, authorized: authorized)
  end

  # The editor's test case: a real sale (by folio) or a made-up one with product codes, total,
  # payment method and hour.
  def self.scenario(params, branch)
    folio = params[:sale].to_s.strip.upcase.presence
    { sale_folio: folio, sale: (Sale.where(branch: branch).find_by(folio: folio) if folio),
      keys: params[:keys].presence || Product.active.order(:name).limit(2).pluck(:key).join(", "),
      total: params[:total].present? ? Money.cents(params[:total]) : 25_000, payment_method: params[:payment_method].presence_in(Payment::PAYMENT_METHODS) || "cash",
      hour: (params[:hour].presence || Time.current.hour).to_i.clamp(0, 23), authorized: params[:authorized] == "1" }
  end

  def self.dry_run(code, scenario)
    raise Lisp::Error, I18n.t("price_rule.sale_not_found", folio: scenario[:sale_folio]) if scenario[:sale_folio] && !scenario[:sale]
    evaluate(code, scenario[:sale] ? from_sale(scenario[:sale], scenario[:authorized]) : made_up(scenario))
  end

  def self.from_sale(sale, authorized)
    Input.new(total: sale.total_cents, change: sale.change_cents, rows: sale.lines.includes(:product).map { |l| { key: l.product.key, quantity: l.quantity } },
              payments: sale.payments.group(:payment_method).sum(:amount_cents), moment: sale.created_at, authorized: authorized)
  end

  def self.made_up(scenario)
    rows = scenario[:keys].split(",").map(&:strip).compact_blank.map { |k| { key: k.upcase, quantity: BigDecimal("1") } }
    Input.new(total: scenario[:total], change: 0, rows: rows, payments: { scenario[:payment_method] => scenario[:total] },
              moment: Time.current.change(hour: scenario[:hour]), authorized: scenario[:authorized])
  end

  def self.texts = "sale_rule"

  def self.interpolate(_data) = {}

  def self.functions(data)
    money = ->(c) { BigDecimal(c.to_i) / 100 }
    {
      "total" => -> { money.(data.total) },
      "change" => -> { money.(data.change) },
      "paid-with" => ->(payment_method) { money.(data.payments.fetch(PAYMENT_METHODS[payment_method] || raise(Lisp::Error, I18n.t("sale_rule.payment_method", payment_methods: PAYMENT_METHODS.keys.join(" :"))), 0)) },
      "lines" => -> { data.rows.size },
      "products" => -> { data.rows.map { |r| r[:key] }.uniq },
      "quantity-of" => ->(key) { data.rows.select { |r| r[:key] == key.to_s.upcase }.sum(BigDecimal("0")) { |r| r[:quantity] } },
      "hour" => -> { data.moment.hour },
      "weekday" => -> { data.moment.to_date.cwday },
      "authorized" => -> { data.authorized }
    }
  end

  private_class_method :functions, :interpolate, :texts, :from_sale, :made_up
end
