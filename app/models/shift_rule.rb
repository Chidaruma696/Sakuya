# The till closing hook: a program in Sakuya's Lisp looks at how the count came out and proposes
# what to do with the difference. The rule only reads and returns a decision; the controller closes
# the shift, the usual way.
#
# Contract v1. It gets, in money: (difference) counted − expected (negative = money missing),
# (counted), (expected), (float), (sales), (cash-sales), (returns), (withdrawals), (limit) the cap
# from Settings › Till (0 = no cap); plus (tickets) and (authorized), which is true if whoever
# closes has the till.difference permission. Returns (allow), (to-review reason) or
# (reject reason); the reason is a string or one of the keywords Sakuya translates.
module ShiftRule
  VERSION = 1

  DEFAULT = <<~LISP
    ; Closing the cash drawer. (difference) is counted minus expected: negative means missing money.
    ; Answer (allow), (to-review "why") or (reject "why").
    ; Out of the limit it stops: only someone allowed to accept differences can close, and it goes to review.
    (if (or (= (limit) 0)
            (<= (abs (difference)) (limit)))
        (allow)
        (reject :over-limit))
  LISP

  # The keywords the core can say in the language of whoever closes.
  REASONS = %i[over-limit].freeze

  extend Hook

  SCENARIO = "rules/scenario_shift".freeze # the editor's test case

  # Decides with the current rule (or the built-in one).
  def self.decide(shift, counted_cents:, user:, code: Rule.current("shift")&.code)
    decide_with(code, Input.new(shift, counted_cents, user))
  end

  def self.texts = "shift_rule"

  def self.interpolate(data)
    { difference: Money.format_money(data.difference), cap: Money.format_money(Shift.difference_cap_cents) }
  end

  def self.functions(data)
    {
      "difference" => -> { data.money(data.difference) },
      "counted" => -> { data.money(data.counted) },
      "expected" => -> { data.money(data.expected) },
      "float" => -> { data.money(data.shift.float_cents) },
      "sales" => -> { data.money(data.shift.sales_total_cents) },
      "cash-sales" => -> { data.money(data.shift.cash_sales_cents) },
      "returns" => -> { data.money(data.shift.refunds_cents) },
      "withdrawals" => -> { data.money(data.shift.withdrawals_cents) },
      "limit" => -> { data.money(Shift.difference_cap_cents) },
      "tickets" => -> { data.shift.sales.count },
      "authorized" => -> { data.authorized? }
    }
  end

  private_class_method :functions, :interpolate, :texts

  # The count being closed, in cents; the program reads it in currency units. For trying it in the
  # editor, `authorized` says by hand whether whoever closes has permission.
  class Input
    attr_reader :shift, :counted

    def initialize(shift, counted, user = nil, authorized: nil)
      @shift = shift
      @counted = counted.to_i
      @user = user
      @authorized = authorized
    end

    def expected = @expected ||= shift.expected_cash_cents
    def difference = counted - expected
    def authorized? = @authorized.nil? ? @user.can?("till.difference") : @authorized
    def money(cents) = BigDecimal(cents.to_i) / 100
  end

  # The editor's test case: by default, the real open shift (with its sales, withdrawals and
  # refunds); if there is none or it is asked for, a made-up one with what is expected in the
  # drawer. Plus what was counted and whether someone with permission closes.
  def self.scenario(params, branch)
    real = Shift.opened_at(branch) unless params[:made_up] == "1"
    expected = real&.expected_cash_cents || (params[:expected].present? ? Money.cents(params[:expected]) : 50_000)
    counted = params[:counted].present? ? Money.cents(params[:counted]) : expected
    { real: real, has_real: Shift.opened_at(branch).present?, expected: expected, counted: counted, authorized: params[:authorized] == "1" }
  end

  # Read only: with the real shift, it reads what is there; with the made-up one, an unsaved shift.
  def self.dry_run(code, scenario)
    shift = scenario[:real] || Shift.new(float_cents: scenario[:expected])
    evaluate(code, Input.new(shift, scenario[:counted], authorized: scenario[:authorized]))
  end

  FUNCTIONS = %w[difference counted expected float sales cash-sales returns withdrawals limit tickets authorized].freeze
  EXAMPLE = <<~LISP
    (cond ((> (difference) 0) (to-review "Extra money"))
          ((< (difference) -200) (reject :over-limit))
          (else (allow)))
  LISP
end
