# A customer order: what they want and for when. It carries no price and only sets stock aside
# when `reserve` is on: it is checked out at the till like any sale (with its rules) and then it
# is delivered, linked to that sale.
class Order < ApplicationRecord
  STATUSES = %w[open delivered cancelled].freeze

  belongs_to :customer
  belongs_to :branch
  belongs_to :user
  belongs_to :sale, optional: true
  has_many :lines, class_name: "OrderLine", dependent: :destroy, inverse_of: :order
  accepts_nested_attributes_for :lines, reject_if: ->(a) { a[:product_id].blank? || a[:quantity].blank? }

  before_validation :assign_folio, on: :create

  validates :folio, presence: true, uniqueness: { scope: :branch_id }
  validates :status, inclusion: { in: STATUSES }
  validate(on: :create) { errors.add(:base, I18n.t("errors.order.no_rows")) if lines.empty? }
  validate :suffices_for_reserve, on: :create, if: :reserve

  scope :still_open, -> { where(status: "open") }

  def open? = status == "open"

  def deliver!(sale)
    raise ArgumentError, I18n.t("errors.order.not_open", folio: folio) unless open?
    update!(status: "delivered", sale: sale)
  end

  def cancel!(reason:)
    raise ArgumentError, I18n.t("errors.order.not_open", folio: folio) unless open?
    raise ArgumentError, I18n.t("errors.reason_required") if reason.blank?
    update!(status: "cancelled", cancellation_reason: reason)
  end

  def to_s = folio

  private

  # What gets reserved has to be available (stock minus what other orders have reserved).
  def suffices_for_reserve
    return unless branch
    reserved = Reservations.by_product(branch)
    lines.group_by(&:product).each do |product, ls|
      next unless product
      asks = ls.sum { |l| l.quantity.to_d }
      available = StockLevel.quantity_for(branch, product) - reserved.fetch(product.id, 0)
      next if asks <= available
      qty = ->(v) { ApplicationController.helpers.quantity(v, product) }
      errors.add(:base, I18n.t("errors.order.not_enough", product: product.name, asks: qty.(asks), available: qty.([ available, 0 ].max)))
    end
  end

  def assign_folio
    self.folio ||= Folio.next_number!(branch, "order") if branch
  end
end
