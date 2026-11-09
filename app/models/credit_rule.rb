# The credit hook: when a sale goes wholly or partly on a customer's account, a rule in Sakuya's
# Lisp looks at their account and decides. Out of the box nobody gets credit.
#
# Contract v2. It gets, in money: (amount) what goes on account, (total) the sale total,
# (balance) what they owe before this sale, (limit) their credit limit, (overdue N) what they owe
# from more than N days ago; plus (days-since-payment) the days since their last payment (-1 if
# never), (open-charges) how many charges are unpaid, (oldest-charge-days) the age of the oldest
# one (-1 if nothing is owed), (cutoff-day) their cut-off weekday as a keyword or nil,
# (days-since :friday) the days since the last such weekday, (customer) their name and
# (authorized), true if whoever checks out has customers.force_credit. Returns (allow),
# (to-review reason) or (reject reason).
#
# A business that gives different terms to different customers declares credit types at the top
# level of the rule:
#
#   (credit-type :note-by-note "Note by note"
#     (if (> (open-charges) 0) (reject :open-charge) (allow)))
#
# Declarations are read, never run, to know which types exist (the customer form offers them).
# On a sale the forms that are not declarations run first and then only the body of the
# customer's type. A program without declarations is one rule for every customer, as in v1.
module CreditRule
  VERSION = 2

  DEFAULT = <<~LISP
    ; Selling on account to a customer.
    ; Answer (allow), (to-review "why") or (reject "why").
    ; Out of the box this business gives no credit: write your own rule to allow it.
    (reject :no-credit)
  LISP

  REASONS = %i[no-credit over-limit cash-only open-charge cutoff-passed no-payment no-credit-type].freeze
  FUNCTIONS = %w[amount total balance limit overdue days-since-payment open-charges oldest-charge-days cutoff-day days-since customer authorized].freeze
  WEEKDAYS = %i[sunday monday tuesday wednesday thursday friday saturday].freeze # by Date#wday
  DECLARATION = '(credit-type :key "Name" …)'.freeze # shown in the editor's reference
  EXAMPLE = <<~LISP
    ; Credit types. Give each customer one in Customers; without one they get no credit.

    (define (cutoff-passed? day)          ; an unpaid charge from that day or before
      (>= (oldest-charge-days) (days-since day)))

    (define (days-without-paying)         ; never paid: since their oldest unpaid charge
      (if (< (days-since-payment) 0) (oldest-charge-days) (days-since-payment)))

    ; Never on account.
    (credit-type :cash "Cash only"
      (reject :cash-only))

    ; Pay the previous note to take a new one. Notes from the same day do not
    ; block each other; use (> (open-charges) 0) to allow strictly one.
    (credit-type :note-by-note "Note by note"
      (if (> (oldest-charge-days) 0) (reject :open-charge) (allow)))

    ; What they owe plus this sale must fit under their limit.
    (credit-type :limit "Credit limit"
      (if (> (+ (balance) (amount)) (limit)) (reject :over-limit) (allow)))

    ; On their cut-off day, everything bought up to that day must be paid.
    (credit-type :weekly "Weekly"
      (if (cutoff-passed? (or (cutoff-day) :monday)) (reject :cutoff-passed) (allow)))

    ; May owe, as long as they paid something in the last 7 days.
    (credit-type :paying-down "Cash, paying down"
      (if (and (> (balance) 0) (> (days-without-paying) 7)) (reject :no-payment) (allow)))

    ; No automatic lock unless they have a cut-off day.
    (credit-type :special "Special"
      (if (and (cutoff-day) (cutoff-passed? (cutoff-day))) (reject :cutoff-passed) (allow)))
  LISP

  extend Hook

  SCENARIO = "rules/scenario_credit".freeze # the editor's test case

  # `overdue` is a function: days → cents owed from more than that many days ago.
  Input = Data.define(:customer, :amount, :total, :balance, :limit, :overdue, :days_since_payment, :authorized,
                      :credit_type, :open_charges, :oldest_charge_days, :cutoff_day, :today)

  # A program split in two: the forms every type shares and the declared types, { "key" => Type }.
  Program = Data.define(:shared, :types) do
    def typed? = types.any?
  end
  Type = Data.define(:key, :name, :body)

  # Reads the program without running it; raises Lisp::Error if a declaration is incomplete or repeated.
  def self.read(code)
    shared = []
    types = {}
    Lisp::Reader.read(code).each do |form|
      next shared << form unless form.is_a?(Array) && form.first == Lisp::Sym.new("credit-type")
      key, name, *body = form.drop(1)
      unless key.is_a?(Symbol) && name.is_a?(String) && name.present? && body.any?
        raise Lisp::Error, I18n.t("credit_rule.errors.declaration", form: Lisp.to_text(form).truncate(60))
      end
      raise Lisp::Error, I18n.t("credit_rule.errors.repeated", key: key) if types.key?(key.to_s)
      types[key.to_s] = Type.new(key: key.to_s, name: name, body: body)
    end
    Program.new(shared: shared, types: types)
  end

  # The types a program declares, { "key" => "Name" }; by default, those of the rule in force.
  # A rule that cannot be read declares none.
  def self.types(code = Rule.current("credit")&.code)
    code.blank? ? {} : read(code).types.transform_values(&:name)
  rescue Lisp::Error
    {}
  end

  def self.decide(data, code: Rule.current("credit")&.code)
    return decide_with(code, data) if code.blank?
    judge(code, data)
  rescue Lisp::Error => e
    evaluate(DEFAULT, data, plugins: false).with(error: e.message)
  end

  def self.data(customer, amount:, total:, authorized:)
    account = customer.account
    Input.new(customer: customer.name, amount: amount, total: total, balance: account.balance_cents, limit: customer.credit_limit_cents,
              overdue: ->(days) { account.overdue_cents(days) }, days_since_payment: account.days_since_payment, authorized: authorized,
              credit_type: customer.credit_type, open_charges: account.open_charge_count, oldest_charge_days: account.oldest_charge_days,
              cutoff_day: customer.cutoff_keyword, today: Date.current)
  end

  # The editor's test case: a real customer (with their account, limit, type and cut-off day) or a
  # made-up one with a balance, a limit, a type, unpaid charges and a cut-off day; plus what goes
  # on account and whether someone with permission checks out.
  def self.scenario(params, _branch)
    customer = Customer.active.find_by(id: params[:customer_id]) if params[:customer_id].present?
    { customer: customer, amount: params[:amount].present? ? Money.cents(params[:amount]) : 50_000,
      balance: params[:balance].present? ? Money.cents(params[:balance]) : 0, limit: params[:limit].present? ? Money.cents(params[:limit]) : 200_000,
      credit_type: params[:credit_type].presence, open_charges: [ params[:open_charges].to_i, 0 ].max, oldest_days: [ params[:oldest_days].to_i, 0 ].max,
      cutoff_day: params[:cutoff_day].present? ? WEEKDAYS[params[:cutoff_day].to_i.clamp(0, 6)] : nil,
      authorized: params[:authorized] == "1" }
  end

  def self.dry_run(code, scenario)
    data = if scenario[:customer]
      data(scenario[:customer], amount: scenario[:amount], total: scenario[:amount], authorized: scenario[:authorized])
    else
      owes = scenario[:open_charges].positive?
      Input.new(customer: "", amount: scenario[:amount], total: scenario[:amount], balance: scenario[:balance], limit: scenario[:limit],
                overdue: ->(days) { owes && scenario[:oldest_days] > days ? scenario[:balance] : 0 }, days_since_payment: nil,
                authorized: scenario[:authorized], credit_type: scenario[:credit_type], open_charges: scenario[:open_charges],
                oldest_charge_days: owes ? scenario[:oldest_days] : -1, cutoff_day: scenario[:cutoff_day], today: Date.current)
    end
    judge(code, data)
  end

  # What the editor says before saving: customers whose type the new program stops declaring.
  def self.warning(code)
    program = read(code)
    return unless program.typed?
    dropped = Customer.with_credit_type.where.not(credit_type: program.types.keys).group(:credit_type).count
    return if dropped.empty?
    I18n.t("credit_rule.dropped", count: dropped.values.sum, types: dropped.map { |key, n| ":#{key} (#{n})" }.join(", "))
  end

  def self.texts = "credit_rule"

  def self.interpolate(data)
    { customer: data.customer, balance: Money.format_money(data.balance), limit: Money.format_money(data.limit) }
  end

  def self.functions(data)
    money = ->(c) { BigDecimal(c.to_i) / 100 }
    {
      "amount" => -> { money.(data.amount) },
      "total" => -> { money.(data.total) },
      "balance" => -> { money.(data.balance) },
      "limit" => -> { money.(data.limit) },
      "overdue" => ->(days) { money.(data.overdue.(Lisp::Base.number!(days, "overdue").to_i)) },
      "days-since-payment" => -> { data.days_since_payment || -1 },
      "open-charges" => -> { data.open_charges },
      "oldest-charge-days" => -> { data.oldest_charge_days },
      "cutoff-day" => -> { data.cutoff_day },
      "days-since" => ->(weekday) { (data.today.wday - weekday!(weekday)) % 7 },
      "customer" => -> { data.customer },
      "authorized" => -> { data.authorized }
    }
  end

  def self.weekday!(weekday)
    WEEKDAYS.index(weekday) or raise Lisp::Error, I18n.t("credit_rule.errors.weekday", value: Lisp.to_text(weekday), weekdays: WEEKDAYS.join(" :"))
  end

  # With declared types only the customer's own decides; without a type, or with one the program
  # does not declare, the answer is the built-in one: no credit.
  def self.judge(code, data)
    program = read(code)
    return evaluate_forms(program.shared, data) unless program.typed?
    type = program.types[data.credit_type]
    return Hook::Decision.new(verdict: :reject, reason: I18n.t("credit_rule.reasons.no_credit_type", **interpolate(data)), error: nil) unless type
    evaluate_forms(program.shared + type.body, data)
  end

  private_class_method :functions, :interpolate, :texts, :weekday!, :judge
end
