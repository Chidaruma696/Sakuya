# A physical stock count: the supervisor scans the pieces (and types in whatever is sold in
# fractions), the system compares against the stock level and, on closing, the count rules: the
# inventory is adjusted and the shortage is charged to whoever is responsible.
class StockCount < ApplicationRecord
  belongs_to :branch
  belongs_to :user
  belongs_to :responsible, class_name: "User"
  has_many :lines, class_name: "StockCountLine", dependent: :destroy, inverse_of: :stock_count
  has_many :charges, dependent: :restrict_with_error

  before_validation :assign_folio, on: :create

  validates :folio, presence: true, uniqueness: { scope: :branch_id }
  validates :status, inclusion: { in: %w[open closed] }
  validates :scope, inclusion: { in: %w[total partial] }

  scope :still_open, -> { where(status: "open") }
  scope :closed, -> { where(status: "closed") }

  def open? = status == "open"
  def partial? = scope == "partial"

  # Total: everything at the branch. Partial: only `products` (a list or a whole product line),
  # with or without stock, so surpluses can be counted; nothing else is touched on closing.
  def self.open!(branch:, user:, responsible:, products: nil)
    raise ArgumentError, I18n.t("errors.stock_count.already_open", branch: branch.name) if still_open.exists?(branch: branch)
    raise ArgumentError, I18n.t("errors.stock_count.partial_empty") if products && products.empty?
    transaction do
      count = create!(branch: branch, user: user, responsible: responsible, scope: products ? "partial" : "total")
      if products
        products.each { |p| count.lines.create!(product: p, system: StockLevel.quantity_for(branch, p)) }
      else
        StockLevel.where(branch: branch).where("quantity > 0").includes(:product).each do |level|
          count.lines.create!(product: level.product, system: level.quantity)
        end
      end
      count
    end
  end

  # Is a count due? When the branch counts every N days and the last closed one is older (or there is none).
  def self.overdue?(branch)
    return false unless branch.count_interval_days
    last = closed.where(branch: branch).maximum(:closed_at)
    last.nil? || last < branch.count_interval_days.days.ago
  end

  def line_of(product)
    if partial?
      lines.find_by(product: product) or raise ArgumentError, I18n.t("errors.stock_count.out_of_scope", product: product.name)
    else
      lines.find_or_create_by!(product: product) { |l| l.system = StockLevel.quantity_for(branch, product) }
    end
  end

  # Scanning a product sold by the piece adds one; whatever is sold in fractions is typed in.
  def scan!(product)
    raise ArgumentError, I18n.t("errors.stock_count.closed") unless open?
    raise ArgumentError, I18n.t("errors.stock_count.is_typed", product: product.name) if product.fractional?
    line_of(product).increment!(:scanned, 1)
  end

  # What is typed replaces the previous value, it does not add to it.
  def count_manual!(product, quantity)
    raise ArgumentError, I18n.t("errors.stock_count.closed") unless open?
    quantity = BigDecimal(quantity.to_s).round(3)
    raise ArgumentError, I18n.t("errors.stock_count.invalid_quantity") if quantity.negative?
    line_of(product).update!(manual: quantity)
  end

  def close!(user:)
    raise ArgumentError, I18n.t("errors.stock_count.already_closed") unless open?
    shortage = 0
    surplus = 0
    detail = []
    transaction do
      lines.includes(:product).each do |l|
        system = StockLevel.quantity_for(branch, l.product)
        counted = l.scanned + l.manual
        difference = counted - system
        cents = Money.amount(difference.abs, l.product.price_cents_for(branch))
        l.update!(system: system, difference: difference, difference_cents: difference.negative? ? -cents : cents)
        next if difference.zero?
        Inventory.move!(branch: branch, product: l.product, kind: difference.negative? ? "adjustment_outflow" : "adjustment_inflow",
                          quantity: difference.abs, user: user, reference: self, reason: I18n.t("stock_counts.notices.kardex_reason", folio: folio))
        if difference.negative?
          shortage += cents
          detail << I18n.t("stock_counts.notices.shortage_line", product: l.product.name, quantity: difference.abs.to_s("F"), unit: l.product.unit, amount: Money.format_money(cents))
        else
          surplus += cents
        end
      end
      update!(status: "closed", closed_at: Time.current, shortage_cents: shortage, surplus_cents: surplus)
      charges.create!(user: responsible, branch: branch, amount_cents: shortage, detail: detail.join("\n")) if shortage.positive?
    end
    self
  end

  def to_s
    folio
  end

  private

  def assign_folio
    self.folio ||= Folio.next_number!(branch, "stock_count") if branch
  end
end
