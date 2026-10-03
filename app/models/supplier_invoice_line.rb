class SupplierInvoiceLine < ApplicationRecord
  belongs_to :invoice, class_name: "SupplierInvoice", foreign_key: :supplier_invoice_id, inverse_of: :lines
  belongs_to :product

  validates :quantity, numericality: { greater_than: 0 }
  validates :price_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :boxes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation { self.amount_cents = Money.amount(quantity, price_cents) if quantity && price_cents }

  # The form takes the price in currency units, not cents.
  def price = price_cents && BigDecimal(price_cents) / 100
end
