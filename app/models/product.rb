class Product < ApplicationRecord
  # Kilos, liters and meters are sold in fractions (three decimals); pieces, whole.
  UNITS = %w[kg piece liter meter].freeze
  INITIAL_PLU = 90_000

  has_many :product_barcodes, class_name: "ProductBarcode", dependent: :destroy
  has_many :stock_levels, dependent: :restrict_with_error
  has_many :branch_prices, class_name: "BranchPrice", dependent: :destroy
  has_many :promotions, dependent: :destroy

  before_validation :assign_plu, on: :create

  validates :key, presence: true, uniqueness: true, length: { maximum: 20 }
  validates :name, presence: true
  validates :unit, inclusion: { in: UNITS }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :plu, numericality: { only_integer: true, in: 1..99_999 }, uniqueness: true

  scope :active, -> { where(active: true) }

  def kg?
    unit == "kg"
  end

  def fractional?
    unit != "piece"
  end

  def self.unit_name(unit) = I18n.t("units.#{unit}", default: unit)
  def short_unit = I18n.t("short_units.#{unit}", default: unit)

  def price
    BigDecimal(price_cents) / 100
  end

  def price=(amount)
    self.price_cents = (BigDecimal(amount.to_s) * 100).round.to_i
  end

  # The price in force at a branch: its own if it has one, otherwise the general one.
  def price_cents_for(branch)
    branch_prices.find { |ps| ps.branch_id == branch.id }&.price_cents || price_cents
  end

  # Sets (or removes, with nil) a branch's price.
  def set_price!(branch, amount)
    if amount.blank?
      branch_prices.where(branch: branch).destroy_all
    else
      branch_prices.find_or_initialize_by(branch: branch).update!(price_cents: Money.cents(amount))
    end
  end

  # Last purchase price per unit: the one on the most recent line of an open supplier invoice.
  # It is all the system knows about costs; inventory carries none.
  def last_cost_cents
    SupplierInvoiceLine.joins(:invoice).where(product_id: id, supplier_invoices: { status: "open" })
                         .order("supplier_invoices.date DESC, supplier_invoice_lines.id DESC").pick(:price_cents)
  end

  # Decimals the quantity is entered with: fractions to 3, whole pieces.
  def decimals
    fractional? ? 3 : 0
  end

  def to_s
    name
  end

  private

  def assign_plu
    return if plu.present?
    self.plu = [ Product.maximum(:plu).to_i + 1, INITIAL_PLU ].max
  end
end
