# The returnables hook: goods often leave in something that has to come back (crates, glass
# bottles, cylinders). A business declares its kinds at the top level of the rule, each with the
# rule that decides whether more pieces may leave with a customer:
#
#   (returnable :crate "Crate" :value 85
#     (if (> (owed-after) 10) (reject :too-many-out) (allow)))
#
# A key, a display name, options by keyword (only :value, what one piece is worth) and a body that
# ends in a decision. Declarations are read, never run, to know which kinds exist; when pieces of a
# kind leave, the forms that are not declarations run first and then only the body of that kind.
# Out of the box nothing is declared: no kind exists and nothing is asked.
#
# Contract v1. The body reads, in pieces of its own kind: (owed) what the customer owes before this
# sale, (in-favor) what they have in their favor, (leaving) and (returning) with this sale,
# (owed-after) what they will owe, (oldest-days) the age of the oldest piece still out (-1 if
# none); plus (owed-all) the pieces of every kind they owe, (credit-type) their credit type as a
# keyword or nil, (customer) their name and (authorized), true if whoever checks out has
# returnables.force. Returns (allow), (to-review reason) or (reject reason).
module ReturnableRule
  VERSION = 1

  DEFAULT = <<~LISP
    ; Returnable containers: crates, bottles, cylinders…
    ; Out of the box this business has none. Declare yours with
    ;   (returnable :key "Name" :value 85 rule…)
    ; and each rule answers (allow), (to-review "why") or (reject "why").
  LISP

  REASONS = %i[too-many-out not-returned no-returnables].freeze
  FUNCTIONS = %w[owed in-favor leaving returning owed-after oldest-days owed-all credit-type customer authorized].freeze
  OPTIONS = %i[value].freeze
  DECLARATION = '(returnable :key "Name" :value 85 …)'.freeze # shown in the editor's reference
  EXAMPLE = <<~LISP
    ; Returnable containers. Nothing here is active until you save it.

    ; Up to ten crates out at a time.
    (returnable :crate "Crate" :value 85
      (if (> (owed-after) 10) (reject :too-many-out) (allow)))

    ; Bottles are swapped one for one; the first two cases (48) are on trust,
    ; and nothing more leaves while a bottle has been out for over 30 days.
    (returnable :bottle "Glass bottle" :value 6
      (cond ((> (oldest-days) 30) (reject :not-returned))
            ((> (owed-after) 48) (reject :too-many-out))
            (else (allow))))
  LISP

  extend Hook

  SCENARIO = "rules/scenario_returnable".freeze # the editor's test case

  Input = Data.define(:customer, :kind, :kind_name, :owed, :in_favor, :leaving, :returning, :oldest_days, :owed_all, :credit_type, :authorized)

  # A program split in two: the forms every kind shares and the declared kinds, { "key" => Kind }.
  Program = Data.define(:shared, :kinds)
  Kind = Data.define(:key, :name, :value_cents, :body)

  # Reads the program without running it; raises Lisp::Error if a declaration is incomplete,
  # repeated or carries an option it does not know.
  def self.read(code)
    shared = []
    kinds = {}
    Lisp::Reader.read(code).each do |form|
      next shared << form unless form.is_a?(Array) && form.first == Lisp::Sym.new("returnable")
      key, name, *rest = form.drop(1)
      wrong = -> { raise Lisp::Error, I18n.t("returnable_rule.errors.declaration", form: Lisp.to_text(form).truncate(60)) }
      wrong.() unless key.is_a?(Symbol) && name.is_a?(String) && name.present?
      options = {}
      while rest.first.is_a?(Symbol)
        option = rest.shift
        raise Lisp::Error, I18n.t("returnable_rule.errors.option", key: key, option: option, options: OPTIONS.join(" :")) unless OPTIONS.include?(option)
        wrong.() if rest.empty?
        options[option] = rest.shift
      end
      wrong.() if rest.empty?
      raise Lisp::Error, I18n.t("returnable_rule.errors.repeated", key: key) if kinds.key?(key.to_s)
      kinds[key.to_s] = Kind.new(key: key.to_s, name: name, value_cents: value_cents(key, options[:value]), body: rest)
    end
    Program.new(shared: shared, kinds: kinds)
  end

  # The kinds a program declares, { "key" => Kind }; by default, those of the rule in force.
  # A rule that cannot be read declares none.
  def self.kinds(code = Rule.current("returnable")&.code)
    code.blank? ? {} : read(code).kinds
  rescue Lisp::Error
    {}
  end

  # The same, as { "key" => "Name" }.
  def self.names(code = Rule.current("returnable")&.code) = kinds(code).transform_values(&:name)

  def self.decide(data, code: Rule.current("returnable")&.code)
    return built_in(data) if code.blank?
    judge(code, data)
  rescue Lisp::Error => e
    built_in(data).with(error: e.message)
  end

  # What the rule reads about a customer and a kind, with the pieces this sale moves.
  def self.data(customer, kind:, leaving:, returning:, authorized:, name: nil)
    account = customer.returnable_account
    Input.new(customer: customer.name, kind: kind.to_s, kind_name: name || kinds[kind.to_s]&.name || kind.to_s, owed: account.owed(kind),
              in_favor: account.in_favor(kind), leaving: leaving, returning: returning, oldest_days: account.oldest_days(kind),
              owed_all: account.owed_all, credit_type: customer.credit_type&.to_sym, authorized: authorized)
  end

  # The editor's test case: a real customer (with their count) or a made-up one with pieces owed
  # and the age of the oldest; plus the kind, what leaves, what comes back and whether someone with
  # permission checks out.
  def self.scenario(params, _branch)
    customer = Customer.active.find_by(id: params[:customer_id]) if params[:customer_id].present?
    pieces = ->(key, default) { params[key].present? ? [ params[key].to_i, 0 ].max : default }
    { customer: customer, kind: params[:kind].presence, owed: pieces.(:owed, 0), leaving: pieces.(:leaving, 1), returning: pieces.(:returning, 0),
      oldest_days: pieces.(:oldest_days, 0), authorized: params[:authorized] == "1" }
  end

  def self.dry_run(code, scenario)
    declared = read(code).kinds
    kind = declared[scenario[:kind]] || declared.values.first
    data = if scenario[:customer] && kind
      data(scenario[:customer], kind: kind.key, name: kind.name, leaving: scenario[:leaving], returning: scenario[:returning], authorized: scenario[:authorized])
    else
      Input.new(customer: scenario[:customer]&.name.to_s, kind: kind&.key, kind_name: kind&.name.to_s, owed: scenario[:owed], in_favor: 0,
                leaving: scenario[:leaving], returning: scenario[:returning], oldest_days: scenario[:owed].positive? ? scenario[:oldest_days] : -1,
                owed_all: scenario[:owed], credit_type: scenario[:customer]&.credit_type&.to_sym, authorized: scenario[:authorized])
    end
    judge(code, data)
  end

  # What the editor says before saving: kinds the new program stops declaring while customers
  # still hold pieces of them or products still release them.
  def self.warning(code)
    declared = read(code).kinds.keys
    out = ReturnableMovement.where.not(kind: declared).group(:kind, :customer_id).sum(:quantity).reject { |_, count| count.zero? }
    products = ProductReturnable.where.not(kind: declared).distinct.count(:product_id)
    parts = []
    if out.any?
      kinds = out.keys.map(&:first).uniq.map { |kind| ":#{kind}" }.join(", ")
      parts << I18n.t("returnable_rule.dropped.out", count: out.keys.map(&:last).uniq.size, pieces: out.values.sum(&:abs), kinds: kinds)
    end
    parts << I18n.t("returnable_rule.dropped.products", count: products) if products.positive?
    parts.join(" ").presence
  end

  def self.texts = "returnable_rule"

  def self.interpolate(data)
    { customer: data.customer, kind: data.kind_name, owed: data.owed }
  end

  def self.functions(data)
    {
      "owed" => -> { data.owed },
      "in-favor" => -> { data.in_favor },
      "leaving" => -> { data.leaving },
      "returning" => -> { data.returning },
      "owed-after" => -> { [ data.owed - data.in_favor + data.leaving - data.returning, 0 ].max },
      "oldest-days" => -> { data.oldest_days },
      "owed-all" => -> { data.owed_all },
      "credit-type" => -> { data.credit_type },
      "customer" => -> { data.customer },
      "authorized" => -> { data.authorized }
    }
  end

  # Only the body of the kind decides. A kind the program does not declare gets the built-in
  # answer: it cannot leave. A program that declares nothing is run whole, so that the editor can
  # say what is wrong with it.
  def self.judge(code, data)
    program = read(code)
    kind = program.kinds[data.kind]
    return evaluate_forms(program.shared + kind.body, data) if kind
    return built_in(data) if program.kinds.any? || program.shared.empty?
    evaluate_forms(program.shared, data)
  end

  def self.built_in(data)
    Hook::Decision.new(verdict: :reject, reason: I18n.t("returnable_rule.reasons.no_returnables", **interpolate(data)), error: nil)
  end

  def self.value_cents(key, value)
    return if value.nil?
    raise Lisp::Error, I18n.t("returnable_rule.errors.value", key: key, value: Lisp.to_text(value)) unless value.is_a?(Numeric) && !value.negative?
    (BigDecimal(value.to_s) * 100).round.to_i
  end

  private_class_method :functions, :interpolate, :texts, :judge, :built_in, :value_cents
end
