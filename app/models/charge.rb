# Money charged to someone: the shortage from a stock count or an operation flagged in a review.
class Charge < ApplicationRecord
  belongs_to :user
  belongs_to :branch
  belongs_to :stock_count, optional: true
  belongs_to :review, optional: true
  belongs_to :resolved_by, class_name: "User", optional: true

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: %w[pending paid forgiven] }
  validate { errors.add(:base, I18n.t("errors.charge.no_origin")) if stock_count.nil? && review.nil? }

  scope :pending, -> { where(status: "pending") }

  def resolve!(status, user:)
    raise ArgumentError, I18n.t("errors.charge.already", status: I18n.t("statuses.#{self.status}")) unless self.status == "pending"
    update!(status: status, resolved_by: user, resolved_at: Time.current)
  end
end
