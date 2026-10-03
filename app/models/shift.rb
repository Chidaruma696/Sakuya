# A till shift: opens with a float, accumulates whatever goes through the drawer and closes by counting.
class Shift < ApplicationRecord
  belongs_to :branch
  belongs_to :user
  belongs_to :closed_by, class_name: "User", optional: true
  has_many :sales, dependent: :restrict_with_error
  has_many :withdrawals, dependent: :restrict_with_error
  has_many :refunds, dependent: :restrict_with_error
  has_many :account_payments, dependent: :restrict_with_error

  # { cents => how many } of how the drawer was counted at closing; empty if only the total was typed.
  serialize :breakdown, coder: JSON

  before_validation :assign_folio, on: :create

  validates :folio, presence: true, uniqueness: { scope: :branch_id }
  validates :status, inclusion: { in: %w[open closed] }
  validates :float_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :still_open, -> { where(status: "open") }

  def open? = status == "open"

  def self.opened_at(branch)
    still_open.find_by(branch: branch)
  end

  # Bills and coins the drawer is counted with, in cents and from largest to smallest (Settings › Till).
  def self.denominations
    Setting["till.denominations"].delete(" ").split(",").map { |d| Money.cents(d) }.select(&:positive?).uniq.sort.reverse
  end

  # Difference (counted − expected) from which the built-in shift rule asks for a reason; 0 = no cap.
  def self.difference_cap_cents
    Setting.integer("till.difference_cap") * 100
  end

  # Sum of a breakdown { cents => how many }; anything that is not a valid denomination is ignored.
  def self.add_up(breakdown)
    valid_ones = denominations
    breakdown.to_h.sum { |value, how_many| valid_ones.include?(value.to_i) ? value.to_i * how_many.to_i : 0 }
  end

  # One open shift per branch.
  def self.open!(branch:, user:, float_cents:)
    raise ArgumentError, I18n.t("errors.shift.no_till_in_warehouse", branch: branch.name) unless branch.till?
    raise ArgumentError, I18n.t("errors.shift.already_open", branch: branch.name) if opened_at(branch)
    create!(branch: branch, user: user, float_cents: float_cents, opened_at: Time.current)
  end

  # Sales whose money came in (paid, or refunded later).
  def paid_sales
    sales
  end

  # Cash that came in from sales: what was paid in cash minus the change given back.
  def cash_sales_cents
    Payment.where(sale: paid_sales, payment_method: "cash").sum(:amount_cents) - paid_sales.sum(:change_cents)
  end

  def sales_total_cents
    paid_sales.sum(:total_cents)
  end

  # What left the drawer for refunds (refunds of sales on account lower the customer's debt instead).
  def refunds_cents
    refunds.sum("total_cents - on_account_cents")
  end

  # What customers paid into their accounts in cash during the shift.
  def cash_account_payments_cents
    account_payments.where(payment_method: "cash").sum(:amount_cents)
  end

  def withdrawals_cents
    withdrawals.sum(:amount_cents)
  end

  # What should be in the drawer right now.
  def expected_cash_cents
    float_cents + cash_sales_cents + cash_account_payments_cents - refunds_cents - withdrawals_cents
  end

  def exceeds_limit?
    expected_cash_cents > branch.cash_limit_cents
  end

  def withdraw!(amount_cents:, reason:, user:, authorized_by: nil)
    check_withdrawal!(amount_cents, reason)
    withdrawals.create!(amount_cents: amount_cents.to_i, reason: reason, user: user, authorized_by: authorized_by)
  end

  # What a withdrawal needs before asking anyone: an open shift, a reason and enough cash.
  def check_withdrawal!(amount_cents, reason)
    raise ArgumentError, I18n.t("errors.shift.closed") unless open?
    raise ArgumentError, I18n.t("errors.reason_required") if reason.blank?
    raise ArgumentError, I18n.t("errors.shift.no_cash", amount: Money.format_money(expected_cash_cents)) if amount_cents.to_i > expected_cash_cents
  end

  # Closes by counting: with the breakdown by denomination (the total comes from it) or with the typed total.
  def close!(counted_cents: nil, user:, breakdown: nil)
    raise ArgumentError, I18n.t("errors.shift.already_closed") unless open?
    valid_ones = self.class.denominations
    clean = breakdown.to_h.to_h { |v, c| [ v.to_i, c.to_i ] }.select { |v, c| valid_ones.include?(v) && c.positive? }
    counted = clean.any? ? self.class.add_up(clean) : counted_cents.to_i
    expected = expected_cash_cents
    update!(status: "closed", counted_cents: counted, expected_cents: expected, breakdown: clean.presence,
            difference_cents: counted - expected, closed_at: Time.current, closed_by: user)
  end

  # "3 × $500, 8 × $100", to show how it was counted.
  def breakdown_text
    (breakdown || {}).sort_by { |v, _| -v.to_i }.map { |v, c| "#{c} × #{Money.format_money(v.to_i)}" }.join(", ")
  end

  def to_s
    folio
  end

  private

  def assign_folio
    self.folio ||= Folio.next_number!(branch, "shift") if branch
  end
end
