# Money a customer pays into their account. It goes into the till open at that moment (into the
# drawer, if it is cash) and stays on their account as a payment. Insert only.
class AccountPayment < ApplicationRecord
  belongs_to :customer
  belongs_to :branch
  belongs_to :shift
  belongs_to :user

  before_validation :assign_folio, on: :create

  validates :folio, presence: true, uniqueness: { scope: :branch_id }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :payment_method, inclusion: { in: Payment::PAYMENT_METHODS }

  before_update { raise ActiveRecord::ReadOnlyRecord, "account payments cannot be edited" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "account payments cannot be deleted" }

  def self.register!(customer:, branch:, user:, amount_cents:, payment_method:, notes: nil)
    raise ArgumentError, I18n.t("errors.account_payment.greater_than_zero") unless amount_cents.to_i.positive?
    shift = Shift.opened_at(branch) or raise ArgumentError, I18n.t("errors.account_payment.no_till", branch: branch.name)
    transaction do
      account_payment = create!(customer: customer, branch: branch, shift: shift, user: user, amount_cents: amount_cents.to_i, payment_method: payment_method, notes: notes.presence)
      customer.credit_movements.create!(kind: "account_payment", amount_cents: -account_payment.amount_cents, date: Date.current, reference: account_payment,
                                          branch: branch, user: user, reason: I18n.t("customers.account.account_payment", folio: account_payment.folio, payment_method: I18n.t("payment_methods.#{payment_method}")))
      account_payment
    end
  end

  def to_s = folio

  private

  def assign_folio
    self.folio ||= Folio.next_number!(branch, "account_payment") if branch
  end
end
