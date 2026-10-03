# Stock transfer: goods moving between branches. They leave the origin and enter the destination
# in the same transaction, with a TG folio per origin branch. From a warehouse, goods only go to
# the head office: they gather there and go out from there.
# TODO: that rule belongs to the business, not the system; let a Lisp rule decide it.
class StockTransfer < ApplicationRecord
  class Error < ArgumentError; end

  belongs_to :origin_branch, class_name: "Branch"
  belongs_to :destination_branch, class_name: "Branch"
  belongs_to :user
  has_many :lines, class_name: "StockTransferLine", dependent: :destroy, inverse_of: :stock_transfer
  # Only so the form names its rows lines_attributes; the core builds the lines.
  accepts_nested_attributes_for :lines
  has_many :movements, as: :reference

  before_validation :assign_folio, on: :create
  validates :folio, presence: true, uniqueness: { scope: :origin_branch_id }
  validates :date, presence: true
  validates :status, inclusion: { in: %w[registered cancelled] }
  validate { errors.add(:destination_branch, I18n.t("errors.stock_transfer.same_place")) if origin_branch_id == destination_branch_id }

  scope :registered, -> { where(status: "registered") }

  def registered? = status == "registered"
  def cancelled? = status == "cancelled"
  def to_s = folio

  # `key` is the browser's idempotency key: the same key returns the same transfer.
  def self.register!(origin:, destination:, user:, lines:, notes: nil, date: Date.current, key: nil)
    transaction do
      if key.present? && (previous = find_by(origin_branch: origin, key: key))
        return previous
      end
      raise Error, I18n.t("errors.stock_transfer.same_place") if origin.id == destination.id
      raise Error, I18n.t("errors.stock_transfer.external_only_to_head_office", warehouse: origin.name) if origin.warehouse? && !destination.head_office?
      clean = lines.map { |l| l.to_h.symbolize_keys }.reject { |l| l[:product_id].blank? || BigDecimal(l[:quantity].to_s.presence || "0") <= 0 }
      raise Error, I18n.t("errors.purchases.no_rows") if clean.empty?
      Reservations.check!(origin, clean.map { |l| [ Product.active.find(l[:product_id]), BigDecimal(l[:quantity].to_s) ] })
      stock_transfer = create!(origin_branch: origin, destination_branch: destination, user: user, notes: notes.presence, date: date, key: key.presence)
      clean.each do |l|
        product = Product.active.find(l[:product_id])
        line = stock_transfer.lines.create!(product: product, quantity: l[:quantity], boxes: l[:boxes].to_i)
        reason = I18n.t("stock_transfers.notices.reason", folio: stock_transfer.folio, origin: origin.name, destination: destination.name)
        Inventory.move!(branch: origin, product: product, kind: "outflow", quantity: line.quantity, user: user, reference: stock_transfer, reason: reason, date: date)
        Inventory.move!(branch: destination, product: product, kind: "inflow", quantity: line.quantity, user: user, reference: stock_transfer, reason: reason, date: date)
      end
      stock_transfer
    end
  end

  # Cancelling sends the goods back (if the destination still has them).
  def cancel!(reason:, user:)
    raise Error, I18n.t("errors.reason_required") if reason.blank?
    raise Error, I18n.t("errors.stock_transfer.already_cancelled") unless registered?
    transaction do
      reason_kardex = I18n.t("stock_transfers.notices.cancellation", folio: folio, reason: reason)
      lines.includes(:product).each do |l|
        Inventory.move!(branch: destination_branch, product: l.product, kind: "adjustment_outflow", quantity: l.quantity, user: user, reference: self, reason: reason_kardex)
        Inventory.move!(branch: origin_branch, product: l.product, kind: "adjustment_inflow", quantity: l.quantity, user: user, reference: self, reason: reason_kardex)
      end
      update!(status: "cancelled", cancellation_reason: reason)
    end
    self
  end

  private

  def assign_folio
    self.folio ||= Folio.next_number!(origin_branch, "stock_transfer") if origin_branch
  end
end
