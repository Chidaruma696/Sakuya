# A payment to a supplier. A single path: if it is cash it comes out of the open drawer as a
# withdrawal, and in the same transaction it is posted to the ledger. Voiding it offsets the
# payment and returns the cash.
class SupplierPayment < ApplicationRecord
  self.table_name = "supplier_payments"

  belongs_to :supplier
  belongs_to :invoice, class_name: "SupplierInvoice", foreign_key: :supplier_invoice_id, optional: true
  belongs_to :branch
  belongs_to :shift, optional: true
  belongs_to :withdrawal, optional: true
  belongs_to :user
  belongs_to :voided_by, class_name: "User", optional: true

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :payment_method, inclusion: { in: Payment::PAYMENT_METHODS }
  validates :status, inclusion: { in: %w[current voided] }

  scope :in_force, -> { where(status: "current") }

  def current? = status == "current"
end
