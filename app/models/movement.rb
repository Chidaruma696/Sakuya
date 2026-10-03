class Movement < ApplicationRecord
  INFLOWS = %w[inflow receipt customer_return adjustment_inflow].freeze
  OUTFLOWS = %w[sale outflow waste adjustment_outflow].freeze
  KINDS = (INFLOWS + OUTFLOWS).freeze
  # Fallback names; the real ones come from movements.* in config/locales.
  NAMES = {
    "inflow" => "Inflow", "receipt" => "Receipt",
    "customer_return" => "Customer return", "adjustment_inflow" => "Adjustment (+)",
    "sale" => "Sale", "outflow" => "Outflow", "waste" => "Waste", "adjustment_outflow" => "Adjustment (−)"
  }.freeze

  belongs_to :branch
  belongs_to :product
  belongs_to :reference, polymorphic: true, optional: true
  belongs_to :user

  validates :kind, inclusion: { in: KINDS }
  validates :quantity, numericality: { greater_than: 0 }
  validates :business_date, presence: true

  # The kardex is never touched: no updates and no deletes.
  before_update { raise ActiveRecord::ReadOnlyRecord, "movements cannot be edited" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "movements cannot be deleted" }

  def self.sign(kind)
    return 1 if INFLOWS.include?(kind)
    return -1 if OUTFLOWS.include?(kind)
    raise ArgumentError, I18n.t("errors.movement.unknown_kind", kind: kind)
  end

  def inflow?
    INFLOWS.include?(kind)
  end

  def kind_name
    I18n.t("movements.#{kind}", default: NAMES[kind])
  end
end
