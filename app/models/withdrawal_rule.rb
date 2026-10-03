# The withdrawals hook: before taking cash out of the drawer, a rule in Sakuya's Lisp looks at how
# much and what for, and decides. The core makes sure, before asking, that there is a reason and
# that no more is taken than there is.
#
# Contract v1. It gets, in money: (amount) what comes out, (cash) what is in the drawer before the
# withdrawal, (withdrawn) what was already withdrawn in the shift, (cash-limit) the branch's cash
# limit; plus (reason) the written reason and (authorized), true if whoever withdraws has
# till.withdraw. Returns (allow), (to-review reason) or (reject reason).
module WithdrawalRule
  VERSION = 1

  DEFAULT = <<~LISP
    ; Taking cash out of the drawer. (amount) is what comes out; (cash) is what the drawer has now.
    ; Answer (allow), (to-review "why") or (reject "why").
    ; Without permission to withdraw it stops and the attempt is reported.
    (if (authorized)
        (allow)
        (reject :needs-permission))
  LISP

  REASONS = %i[needs-permission].freeze
  FUNCTIONS = %w[amount cash withdrawn cash-limit reason authorized].freeze
  EXAMPLE = <<~LISP
    (cond ((not (authorized)) (reject :needs-permission))
          ((> (amount) 5000) (to-review "Big withdrawal"))
          (else (allow)))
  LISP

  extend Hook

  SCENARIO = "rules/scenario_withdrawal".freeze # the editor's test case

  Input = Data.define(:amount, :in_drawer, :withdrawn, :limit, :reason, :authorized) do
    def money(cents) = BigDecimal(cents.to_i) / 100
  end

  def self.decide(shift, amount_cents:, reason:, user:, code: Rule.current("withdrawal")&.code)
    decide_with(code, data(shift, amount_cents, reason, user.can?("till.withdraw")))
  end

  def self.data(shift, amount, reason, authorized)
    Input.new(amount: amount.to_i, in_drawer: shift.expected_cash_cents, withdrawn: shift.withdrawals_cents,
              limit: shift.branch&.cash_limit_cents.to_i, reason: reason.to_s, authorized: authorized)
  end

  # The editor's test case: by default, against the real open shift (what is there and what was
  # already withdrawn); if there is none or it is asked for, with whatever amount is said to be
  # there. Plus how much comes out, what for and whether someone with permission withdraws it.
  def self.scenario(params, branch)
    real = Shift.opened_at(branch) unless params[:made_up] == "1"
    in_drawer = real&.expected_cash_cents || (params[:in_drawer].present? ? Money.cents(params[:in_drawer]) : 50_000)
    { real: real, has_real: Shift.opened_at(branch).present?, amount: params[:amount].present? ? Money.cents(params[:amount]) : 10_000, in_drawer: in_drawer,
      withdrawn: real&.withdrawals_cents.to_i, reason: params[:reason].presence || I18n.t("withdrawal_rule.scenario.reason_example"),
      authorized: params[:authorized] == "1", limit: branch.cash_limit_cents.to_i }
  end

  def self.dry_run(code, scenario)
    evaluate(code, Input.new(amount: scenario[:amount], in_drawer: scenario[:in_drawer], withdrawn: scenario[:withdrawn], limit: scenario[:limit], reason: scenario[:reason], authorized: scenario[:authorized]))
  end

  def self.texts = "withdrawal_rule"

  def self.interpolate(data) = { amount: Money.format_money(data.amount) }

  def self.functions(data)
    {
      "amount" => -> { data.money(data.amount) },
      "cash" => -> { data.money(data.in_drawer) },
      "withdrawn" => -> { data.money(data.withdrawn) },
      "cash-limit" => -> { data.money(data.limit) },
      "reason" => -> { data.reason },
      "authorized" => -> { data.authorized }
    }
  end

  private_class_method :functions, :interpolate, :texts, :data
end
