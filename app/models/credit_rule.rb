# The credit hook: when a sale goes wholly or partly on a customer's account, a rule in Sakuya's
# Lisp looks at their account and decides. Out of the box nobody gets credit.
#
# Contract v1. It gets, in money: (amount) what goes on account, (total) the sale total,
# (balance) what they owe before this sale, (limit) their credit limit, (overdue N) what they owe
# from more than N days ago; plus (days-since-payment) the days since their last payment (-1 if
# never), (customer) their name and (authorized), true if whoever checks out has
# customers.force_credit. Returns (allow), (to-review reason) or (reject reason).
module CreditRule
  VERSION = 1

  DEFAULT = <<~LISP
    ; Selling on account to a customer.
    ; Answer (allow), (to-review "why") or (reject "why").
    ; Out of the box this business gives no credit: write your own rule to allow it.
    (reject :no-credit)
  LISP

  REASONS = %i[no-credit over-limit].freeze
  FUNCTIONS = %w[amount total balance limit overdue days-since-payment customer authorized].freeze
  EXAMPLE = <<~LISP
    (cond ((> (overdue 30) 0) (reject "Owes from more than 30 days ago"))
          ((> (+ (balance) (amount)) (limit)) (reject :over-limit))
          (else (allow)))
  LISP

  extend Hook

  SCENARIO = "rules/scenario_credit".freeze # the editor's test case

  # `overdue` is a function: days → cents owed from more than that many days ago.
  Input = Data.define(:customer, :amount, :total, :balance, :limit, :overdue, :days_since_payment, :authorized)

  def self.decide(data, code: Rule.current("credit")&.code)
    decide_with(code, data)
  end

  def self.data(customer, amount:, total:, authorized:)
    account = customer.account
    Input.new(customer: customer.name, amount: amount, total: total, balance: account.balance_cents, limit: customer.credit_limit_cents,
              overdue: ->(days) { account.overdue_cents(days) }, days_since_payment: account.days_since_payment, authorized: authorized)
  end

  # The editor's test case: a real customer (with their account and limit) or a made-up one with
  # a balance and a limit; plus what goes on account and whether someone with permission checks out.
  def self.scenario(params, _branch)
    customer = Customer.active.find_by(id: params[:customer_id]) if params[:customer_id].present?
    { customer: customer, amount: params[:amount].present? ? Money.cents(params[:amount]) : 50_000,
      balance: params[:balance].present? ? Money.cents(params[:balance]) : 0, limit: params[:limit].present? ? Money.cents(params[:limit]) : 200_000,
      authorized: params[:authorized] == "1" }
  end

  def self.dry_run(code, scenario)
    data = if scenario[:customer]
      data(scenario[:customer], amount: scenario[:amount], total: scenario[:amount], authorized: scenario[:authorized])
    else
      Input.new(customer: "", amount: scenario[:amount], total: scenario[:amount], balance: scenario[:balance], limit: scenario[:limit], overdue: ->(_) { 0 },
                days_since_payment: nil, authorized: scenario[:authorized])
    end
    evaluate(code, data)
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
      "customer" => -> { data.customer },
      "authorized" => -> { data.authorized }
    }
  end

  private_class_method :functions, :interpolate, :texts
end
