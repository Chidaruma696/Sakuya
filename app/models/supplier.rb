# Whoever supplies us. The balance (what we owe them) always comes from their ledger
# (supplier_movements), never from a column.
class Supplier < ApplicationRecord
  self.table_name = "suppliers"

  has_many :invoices, class_name: "SupplierInvoice", dependent: :restrict_with_error
  has_many :receipts, dependent: :restrict_with_error
  has_many :movements, class_name: "SupplierMovement", dependent: :restrict_with_error
  has_many :payments, class_name: "SupplierPayment", dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :credit_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }

  def balance_cents = movements.sum(:delta_cents)

  def to_s = name
end
