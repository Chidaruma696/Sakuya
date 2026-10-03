# The ledger of what is owed to the supplier, insert only: charge (invoice), payment and adjustment
# (cancellations, signed). The balance is the sum of the deltas.
class SupplierMovement < ApplicationRecord
  self.table_name = "supplier_movements"

  belongs_to :supplier
  belongs_to :branch
  belongs_to :user
  belongs_to :invoice, class_name: "SupplierInvoice", foreign_key: :supplier_invoice_id, optional: true
  belongs_to :payment, class_name: "SupplierPayment", foreign_key: :supplier_payment_id, optional: true

  validates :kind, inclusion: { in: %w[charge payment adjustment] }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }

  before_update { raise ActiveRecord::ReadOnlyRecord, "the supplier ledger cannot be edited" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "the supplier ledger cannot be deleted" }
end
