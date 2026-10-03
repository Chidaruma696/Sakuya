# The supplier invoice: the only thing that creates debt, with lines that are the only place the
# purchase price lives. The amount is derived from the lines; without lines (freight, ice) the
# typed amount is accepted. It gets linked to receipts later, and invoicing never touches inventory.
class SupplierInvoice < ApplicationRecord
  self.table_name = "supplier_invoices"

  belongs_to :supplier
  belongs_to :branch
  belongs_to :user
  has_many :lines, class_name: "SupplierInvoiceLine", dependent: :destroy, inverse_of: :invoice
  # Only so the form names its rows lines_attributes; the core builds the lines.
  accepts_nested_attributes_for :lines
  has_many :receipts, dependent: :nullify
  has_many :payments, class_name: "SupplierPayment", dependent: :restrict_with_error
  has_many :movements, class_name: "SupplierMovement", dependent: :restrict_with_error

  validates :folio, presence: true, uniqueness: { scope: :supplier_id }
  validates :date, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: %w[open cancelled] }

  scope :still_open, -> { where(status: "open") }

  def open? = status == "open"
  def cancelled? = status == "cancelled"
  def paid_cents = payments.in_force.sum(:amount_cents)
  def remaining_cents = amount_cents - paid_cents
  def paid? = remaining_cents <= 0
  def overdue? = open? && !paid? && due.present? && due < Date.current

  # How what was received compares with what was invoiced: no linked receipt, partial (something
  # is still to be received) or complete. Without lines there is nothing to compare: it counts as complete.
  def receipt_status
    return "complete" if lines.empty?
    return "no_receipt" if receipts.none?(&:registered?)
    Purchases.comparison(self).any? { |c| %w[shortage not_received].include?(c.status) } ? "partial" : "complete"
  end

  def to_s = folio
end
