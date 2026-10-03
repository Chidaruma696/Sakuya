# The Home dashboard is described by a program in Sakuya's Lisp: which figures show up, in what
# order, which ones are computed the business's own way and which lists go below. The program only
# reads (sales, tickets, stock levels…) and returns the description; the view draws it. If it
# blows up, the built-in one shows instead and whoever can edit it sees why.
module Dashboard
  VERSION = 1

  DEFAULT = <<~LISP
    ; The home dashboard. Each (tile ...) is a figure and each (panel ...) a list.
    ; (tile :sales) uses a built-in figure; (tile "Label" value :money) makes your own.
    (dashboard
      (tile :sales)
      (tile :tickets)
      (tile :average-ticket)
      (tile :returns)
      (tile :cash)
      (tile :transfers)
      (tile :deposits)
      (tile :stock-value)
      (panel :top-products)
      (panel :closed-cash-counts)
      (panel :stock-counts))
  LISP

  FORMATS = %i[money number percent].freeze
  PANELS = %i[top-products closed-cash-counts stock-counts].freeze

  # Built-in figures: the key of their name, their format and where they come from.
  FIGURES = {
    sales: [ "home.sales", :money, :sales ],
    tickets: [ "home.tickets", :number, :tickets ],
    "average-ticket": [ "home.average_ticket", :money, :average_ticket ],
    returns: [ "home.refunds", :money, :refunds ],
    cash: [ "home.cash", :money, :cash ],
    transfers: [ "home.transfers", :money, :transfers ],
    deposits: [ "home.deposits", :money, :deposits ],
    "stock-value": [ "home.inventory_valued", :money, :stock_value ],
    payable: [ "purchases.owed", :money, :payable ],
    "to-review": [ "reviews.title", :number, :pending_review ]
  }.freeze

  Piece = Data.define(:kind, :title, :value, :format, :panel, :limit)

  # Builds the dashboard with the business's program (or the built-in one). Returns (pieces, error).
  def self.build(data, code: Rule.current("dashboard")&.code)
    return [ evaluate(DEFAULT, data, plugins: false), nil ] if code.blank?
    [ evaluate(code, data), nil ]
  rescue Lisp::Error => e
    [ evaluate(DEFAULT, data, plugins: false), e.message ]
  end

  # Evaluates a program and returns its pieces, or raises Lisp::Error with what failed.
  def self.evaluate(code, data, plugins: true)
    result = Lisp.run(code, functions: functions(data), steps: 20_000, prelude: plugins ? Plugin.prelude : [])
    unless result.is_a?(Hash) && result[:kind] == :dashboard
      raise Lisp::Error, I18n.t("dashboard.errors.missing_dashboard")
    end
    result[:pieces]
  end

  def self.functions(data)
    reading = FIGURES.to_h { |name, (_, _, method)| [ name.to_s, -> { data.public_send(method) } ] }
    reading.merge(
      "days" => -> { data.days },
      "sold" => ->(key) { data.sold(key) },
      "sales-of" => ->(key) { data.sold_amount(key) },
      "tile" => Lisp::Native.new(name: "tile", arity: 1..3, with_evaluator: false, block: ->(*args) { tile(data, *args) }),
      "panel" => Lisp::Native.new(name: "panel", arity: 1..2, with_evaluator: false, block: ->(*args) { panel(*args) }),
      "dashboard" => ->(*pieces) { { kind: :dashboard, pieces: pieces.flatten.compact.each { |p| check_piece!(p) } } }
    )
  end

  def self.tile(data, title, value = nil, format = nil)
    if title.is_a?(Symbol)
      key, default, method = FIGURES[title] || raise(Lisp::Error, I18n.t("dashboard.errors.unknown_figure", figure: title, figures: FIGURES.keys.join(" :")))
      title = I18n.t(key)
      value = data.public_send(method) if value.nil?
      format ||= default
    end
    raise Lisp::Error, I18n.t("dashboard.errors.title") unless title.is_a?(String)
    raise Lisp::Error, I18n.t("dashboard.errors.value", title: title) unless value.is_a?(Numeric) || value.is_a?(String)
    format ||= :number
    raise Lisp::Error, I18n.t("dashboard.errors.format", formats: FORMATS.join(" :")) unless FORMATS.include?(format)
    Piece.new(kind: :tile, title: title, value: value, format: format, panel: nil, limit: nil)
  end

  def self.panel(name, limit = 10)
    raise Lisp::Error, I18n.t("dashboard.errors.panel", panel: name, panels: PANELS.join(" :")) unless PANELS.include?(name)
    raise Lisp::Error, I18n.t("dashboard.errors.limit") unless limit.is_a?(Integer) && limit.between?(1, 50)
    Piece.new(kind: :panel, title: nil, value: nil, format: nil, panel: name, limit: limit)
  end

  def self.check_piece!(piece)
    raise Lisp::Error, I18n.t("dashboard.errors.piece", value: Lisp.to_text(piece)) unless piece.is_a?(Piece)
  end

  private_class_method :tile, :panel, :check_piece!

  # What the program can read, computed only once and only if it asks for it. Money is in
  # currency units (BigDecimal), not cents, which is how the program writes it.
  class Input
    def initialize(branches:, from:, to:, can_review: false)
      @branches = branches
      @from = from
      @to = to
      @can_review = can_review
      @cache = {}
    end

    def range_sales = @range_sales ||= Sale.where(branch: @branches, business_date: @from..@to)

    def sales = money(:sales) { range_sales.sum(:total_cents) }
    def tickets = @cache[:tickets] ||= range_sales.count
    def average_ticket = tickets.zero? ? BigDecimal("0") : (sales / tickets).round(2)
    def refunds = money(:refunds) { Refund.where(sale: range_sales).sum(:total_cents) }
    def cash = money(:cash) { by_payment_method.fetch("cash", 0) - range_sales.sum(:change_cents) }
    def transfers = money(:transfers) { by_payment_method.fetch("transfer", 0) }
    def deposits = money(:deposits) { by_payment_method.fetch("deposit", 0) }
    def stock_value = money(:stock_levels) { StockLevel.where(branch: @branches).joins(:product).sum("stock_levels.quantity * products.price_cents").to_i }
    def payable = money(:payable) { Features.active?("purchases") ? SupplierMovement.sum(:delta_cents) : 0 }
    def pending_review = @cache[:pending_review] ||= (@can_review ? Review.pending.where(branch: @branches).count : 0)
    def days = (@to - @from).to_i + 1

    def sold(key) = lines_for(key).sum(:quantity).then { |c| BigDecimal(c.to_s) }
    def sold_amount(key) = BigDecimal(lines_for(key).sum(:amount_cents)) / 100

    private

    def by_payment_method = @cache[:by_payment_method] ||= Payment.where(sale: range_sales).group(:payment_method).sum(:amount_cents)

    def money(key) = @cache[key] ||= BigDecimal(yield.to_i) / 100

    def lines_for(key)
      raise Lisp::Error, I18n.t("dashboard.errors.key") unless key.is_a?(String)
      product = Product.find_by(key: key.upcase) or raise Lisp::Error, I18n.t("dashboard.errors.product", key: key.upcase)
      SaleLine.where(sale: range_sales, product: product)
    end
  end

  # Sample data for the preview: made-up but believable figures, to see the dashboard full even
  # with no sales today. It does not touch the database; the products it names do have to exist,
  # so a typo shows up just as it would with real data.
  class Sample
    def initialize(from:, to:)
      @from = from
      @to = to
    end

    def sales = BigDecimal("18450.50") * days
    def tickets = 137 * days
    def average_ticket = (sales / tickets).round(2)
    def refunds = BigDecimal("320.00") * days
    def cash = BigDecimal("11200.00") * days
    def transfers = BigDecimal("5430.50") * days
    def deposits = BigDecimal("1500.00") * days
    def stock_value = BigDecimal("245000.00")
    def payable = BigDecimal("38900.00")
    def pending_review = 3
    def days = (@to - @from).to_i + 1

    def sold(key) = BigDecimal((product(key).id * 7 % 40) + 5) * days
    def sold_amount(key) = (sold(key) * BigDecimal(product(key).price_cents) / 100).round(2)

    private

    def product(key)
      raise Lisp::Error, I18n.t("dashboard.errors.key") unless key.is_a?(String)
      Product.find_by(key: key.upcase) or raise Lisp::Error, I18n.t("dashboard.errors.product", key: key.upcase)
    end
  end
end
