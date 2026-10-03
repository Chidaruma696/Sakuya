# A pricing rule. The till applies the best current one that applies to the product, branch and quantity.
class Promotion < ApplicationRecord
  self.table_name = "promotions"

  # Fallback names; the real ones come from promotions.kinds.* in config/locales.
  KINDS = { "price" => "Special price", "percentage" => "Discount %", "by_quantity" => "Price from a quantity" }.freeze

  belongs_to :product

  def self.kind_name(kind) = I18n.t("promotions.kinds.#{kind}", default: KINDS[kind])

  belongs_to :branch, optional: true
  has_many :sale_lines, dependent: :restrict_with_error

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS.keys }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, if: -> { kind != "percentage" }
  validates :percentage, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, if: -> { kind == "percentage" }
  validates :minimum_quantity, numericality: { greater_than: 0 }, if: -> { kind == "by_quantity" }
  validate :validity_consistent

  scope :active, -> { where(active: true) }
  scope :applicable_to, ->(product, branch) { active.where(product: product).where(branch_id: [ nil, branch.id ]) }

  def current?(date = Date.current)
    active && (from.nil? || from <= date) && (to.nil? || to >= date)
  end

  # The resulting price for this quantity, or nil if it does not apply.
  def price_for(quantity, catalog_cents)
    return nil if quantity < minimum_quantity
    case kind
    when "percentage" then (catalog_cents * (1 - percentage / 100)).round.to_i
    else price_cents
    end
  end

  # The best current promotion (the lowest price) for product, branch and quantity.
  def self.best(product, branch, quantity, catalog_cents, date: Date.current)
    applicable_to(product, branch).select { |p| p.current?(date) }
                            .filter_map { |p| (price = p.price_for(quantity, catalog_cents)) && [ price, p ] }
                            .select { |price, _| price < catalog_cents }
                            .min_by(&:first)
  end

  def description
    case kind
    when "price" then I18n.t("promotions.desc.price", price: Money.format_money(price_cents))
    when "percentage" then I18n.t("promotions.desc.percentage", pct: percentage.to_s("F").sub(/\.0+\z/, ""))
    else I18n.t("promotions.desc.by_quantity", price: Money.format_money(price_cents), from: minimum_quantity.to_s("F"), unit: product.unit)
    end
  end

  def to_s
    name
  end

  private

  def validity_consistent
    errors.add(:to, I18n.t("errors.promotion.to_before")) if from && to && to < from
  end
end
