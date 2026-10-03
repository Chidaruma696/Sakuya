# The read-only REPL: asking the live data questions with Sakuya's Lisp. The queries return lists
# of maps ({:folio "B-00012" :total 126.00 …}) that are filtered, sorted and grouped with the
# functions here and the usual ones (map, filter, reduce).
#
# It writes nothing: besides the Lisp only being able to call what it is given, every evaluation
# runs with database writes blocked, with a step limit and a row limit.
#
#   (sum-of :total (sales "2026-10-01" (today)))
#   (sort-by-desc :balance (customers))
#   (count-by :cashier (sales))
module Repl
  ROWS = 500
  STEPS = 200_000

  QUERIES = %w[today days-ago sales sale-lines products stock customers cash-counts reviews rules].freeze
  TOOLS = %w[where sort-by sort-by-desc group-by count-by sum-of pluck take].freeze
  # How they are called, for the REPL reference.
  SIGNATURES = {
    "today" => "(today)", "days-ago" => "(days-ago 7)", "sales" => "(sales [from] [to])", "sale-lines" => "(sale-lines [from] [to])",
    "products" => "(products)", "stock" => "(stock [\"CODE\"])", "customers" => "(customers)", "cash-counts" => "(cash-counts [from] [to])",
    "reviews" => "(reviews)", "rules" => "(rules)", "where" => "(where :key value list)", "sort-by" => "(sort-by :key list)",
    "sort-by-desc" => "(sort-by-desc :key list)", "group-by" => "(group-by :key list)", "count-by" => "(count-by :key list)",
    "sum-of" => "(sum-of :key list)", "pluck" => "(pluck :key list)", "take" => "(take n list)"
  }.freeze

  # Evaluates the text and returns the value; raises Lisp::Error with whatever failed.
  def self.evaluate(text, branches:)
    read_only { Lisp.run(text, functions: functions(branches), steps: STEPS, prelude: Plugin.prelude) }
  end

  # Runs the block with database writes blocked; if anything tries to write, it is an error.
  def self.read_only(&)
    ActiveRecord::Base.while_preventing_writes(&)
  rescue ActiveRecord::ReadOnlyError
    raise Lisp::Error, I18n.t("repl.read_only")
  end

  def self.functions(branches)
    queries(Queries.new(branches)).merge(tools)
  end

  def self.queries(q)
    {
      "today" => -> { Date.current.iso8601 },
      "days-ago" => ->(n) { (Date.current - Lisp::Base.number!(n, "days-ago").to_i).iso8601 },
      "sales" => ->(*range) { q.sales(*range) },
      "sale-lines" => ->(*range) { q.rows(*range) },
      "products" => -> { q.products },
      "stock" => ->(*key) { q.stock_levels(*key) },
      "customers" => -> { q.customers },
      "cash-counts" => ->(*range) { q.shifts(*range) },
      "reviews" => -> { q.reviews },
      "rules" => -> { q.rules }
    }
  end

  def self.tools
    list = ->(l, who) { Lisp::Base.list!(l, who) }
    field = ->(row, k) { row.is_a?(Hash) ? row[k] : raise(Lisp::Error, I18n.t("repl.errors.not_to_map", value: Lisp.to_text(row))) }
    sortable = ->(v) { v.nil? ? [ 1, 0 ] : [ 0, v.is_a?(Numeric) ? v : v.to_s ] }
    {
      "where" => ->(k, v, l) { list.(l, "where").select { |r| field.(r, k) == v } },
      "sort-by" => ->(k, l) { list.(l, "sort-by").sort_by { |r| sortable.(field.(r, k)) } },
      "sort-by-desc" => ->(k, l) { list.(l, "sort-by-desc").sort_by { |r| sortable.(field.(r, k)) }.reverse },
      "group-by" => ->(k, l) { list.(l, "group-by").group_by { |r| field.(r, k) } },
      "count-by" => ->(k, l) { list.(l, "count-by").group_by { |r| field.(r, k) }.transform_values(&:size) },
      "sum-of" => ->(k, l) { list.(l, "sum-of").sum(BigDecimal("0")) { |r| field.(r, k) || 0 } },
      "pluck" => ->(k, l) { list.(l, "pluck").map { |r| field.(r, k) } }
    }
  end

  private_class_method :functions, :queries, :tools

  # The queries themselves: they only read, only from the visible branches, and money comes in
  # currency units, not cents.
  class Queries
    def initialize(branches)
      @branches = branches
    end

    def sales(from = nil, to = nil)
      sales_for(from, to).includes(:branch, :user, :customer).map do |s|
        { folio: s.folio, date: s.business_date.iso8601, branch: s.branch.name, cashier: s.user.name, customer: s.customer&.name,
          total: money(s.total_cents), change: money(s.change_cents), status: s.status }
      end
    end

    def rows(from = nil, to = nil)
      SaleLine.where(sale: sales_for(from, to)).includes(:sale, :product).limit(ROWS + 1).map do |l|
        { folio: l.sale.folio, date: l.sale.business_date.iso8601, code: l.product.key, product: l.product.name,
          quantity: BigDecimal(l.quantity.to_s), price: money(l.price_cents), amount: money(l.amount_cents) }
      end
    end

    def products
      Product.order(:name).limit(ROWS + 1).map do |p|
        { code: p.key, name: p.name, unit: p.unit, price: money(p.price_cents), active: p.active }
      end
    end

    def stock_levels(key = nil)
      levels = StockLevel.where(branch: @branches).includes(:branch, :product).joins(:product).order("products.name")
      levels = levels.where(products: { key: text!(key, "stock").upcase }) if key
      reservations = @branches.to_h { |b| [ b.id, Reservations.by_product(b) ] }
      levels.limit(ROWS + 1).map do |x|
        reserved = BigDecimal(reservations.dig(x.branch_id, x.product_id).to_s.presence || "0")
        { branch: x.branch.name, code: x.product.key, product: x.product.name, quantity: BigDecimal(x.quantity.to_s),
          reserved: reserved, available: BigDecimal(x.quantity.to_s) - reserved }
      end
    end

    def customers
      return [] unless Features.active?("customers")
      balances = CreditMovement.group(:customer_id).sum(:amount_cents)
      Customer.order(:name).limit(ROWS + 1).map do |c|
        { name: c.name, balance: money(balances[c.id] || 0), limit: money(c.credit_limit_cents), active: c.active }
      end
    end

    def shifts(from = nil, to = nil)
      first, last = range(from, to)
      Shift.where(branch: @branches, opened_at: first.beginning_of_day..last.end_of_day).includes(:branch, :user).order(:opened_at).limit(ROWS + 1).map do |s|
        { folio: s.folio, branch: s.branch.name, cashier: s.user.name, status: s.status, opened: s.opened_at.iso8601,
          expected: s.expected_cents && money(s.expected_cents), counted: s.counted_cents && money(s.counted_cents),
          difference: s.difference_cents && money(s.difference_cents) }
      end
    end

    def reviews
      Review.pending.where(branch: @branches).includes(:user, :reviewable).order(:created_at).limit(ROWS + 1).map do |r|
        { when: r.created_at.iso8601, who: r.user.name, what: r.description, reason: r.reason, value: money(r.value_cents), stopped: r.stopped }
      end
    end

    def rules
      Rule::HOOKS.filter_map do |hook|
        r = Rule.current(hook) or next
        { hook: hook, contract: r.version, current: Rule.contract(hook), saved: r.created_at.iso8601, by: r.user.name }
      end
    end

    private

    def sales_for(from, to)
      first, last = range(from, to)
      Sale.where(branch: @branches, business_date: first..last).order(:id).limit(ROWS + 1)
    end

    # No dates, today; one, that day; two, from one to the other. Dates like "2026-10-03".
    def range(from, to)
      first = from ? date!(from) : Date.current
      last = to ? date!(to) : first
      first <= last ? [ first, last ] : [ last, first ]
    end

    def date!(text)
      Date.iso8601(text!(text, "date"))
    rescue Date::Error
      raise Lisp::Error, I18n.t("repl.errors.date", value: text)
    end

    def text!(x, who)
      x.is_a?(String) ? x : raise(Lisp::Error, I18n.t("repl.errors.text", who: who, value: Lisp.to_text(x)))
    end

    def money(cents) = BigDecimal(cents.to_i) / 100
  end
end
