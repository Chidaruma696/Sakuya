# A receipt of goods from a supplier: an inventory inflow with a supplier and a delivery note.
# There is no purchase order; the invoice is linked when it arrives.
class Receipt < ApplicationRecord
  self.table_name = "receipts"

  belongs_to :branch
  belongs_to :supplier
  belongs_to :invoice, class_name: "SupplierInvoice", foreign_key: :supplier_invoice_id, optional: true
  belongs_to :user
  has_many :lines, class_name: "ReceiptLine", dependent: :destroy, inverse_of: :receipt
  # Only so the form names its rows lines_attributes; the core builds the lines.
  accepts_nested_attributes_for :lines
  has_many :movements, as: :reference

  before_validation :assign_folio, on: :create
  validates :folio, presence: true, uniqueness: { scope: :branch_id }
  validates :date, presence: true
  validates :status, inclusion: { in: %w[registered cancelled] }

  scope :registered, -> { where(status: "registered") }

  def registered? = status == "registered"
  def cancelled? = status == "cancelled"

  # { product => quantity } of what was received.
  def by_product = lines.includes(:product).group_by(&:product).transform_values { |ls| ls.sum(&:quantity) }

  def to_s = folio

  private

  def assign_folio
    self.folio ||= Folio.next_number!(branch, "receipt") if branch
  end
end
