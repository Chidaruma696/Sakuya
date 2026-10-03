# Deferred authorization. When an operation needs someone with permission and nobody is around
# (an adjustment, a withdrawal, a price below catalog), the operator does it with a reason and it
# stays here under their name. The supervisor reviews it later: approves or flags it, and if
# flagged can charge it to whoever was responsible. Nothing irregular is ever lost.
class Review < ApplicationRecord
  self.table_name = "reviews"
  STATUSES = %w[pending approved flagged].freeze

  belongs_to :branch
  belongs_to :user
  belongs_to :reviewable, polymorphic: true
  belongs_to :reviewed_by, class_name: "User", optional: true
  has_one :charge, dependent: :nullify

  validates :reason, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :value_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :pending, -> { where(status: "pending") }
  scope :resolved, -> { where.not(status: "pending") }

  # stopped: the operation did not go through (a rule stopped it) and what gets reviewed is the
  # attempt; it hangs off the shift where it happened. A stopped attempt identical to a pending one
  # is not repeated, nor is anything asked for with `no_repeat` (a rule failure, which would show up
  # on every sale).
  def self.open!(record, user:, branch:, reason:, value_cents: 0, stopped: false, no_repeat: false)
    if (stopped || no_repeat) && (equal = pending.find_by(reviewable: record, user: user, reason: reason, stopped: stopped))
      return equal
    end
    create!(reviewable: record, user: user, branch: branch, reason: reason, value_cents: value_cents.to_i, stopped: stopped)
  end

  # What the operation's goods are worth, at the branch's catalog price.
  def self.value(quantity, product, branch)
    (BigDecimal(quantity.to_s) * product.price_cents_for(branch)).round.to_i
  end

  def pending? = status == "pending"

  def approve!(user:, note: nil)
    resolve!("approved", user: user, note: note)
  end

  # Flagged: it stays as irregular and, if an amount is given, it is charged to whoever was responsible.
  def flag!(user:, note: nil, charge_cents: 0)
    transaction do
      resolve!("flagged", user: user, note: note)
      if charge_cents.to_i.positive?
        create_charge!(user: self.user, branch: branch, amount_cents: charge_cents.to_i,
                      detail: [ description, reason, note ].compact_blank.join("\n"))
      end
    end
    self
  end

  # What was done, in one line.
  def description
    return I18n.t("reviews.desc.stopped_product", product: reviewable.name) if stopped? && reviewable.is_a?(Product)
    return I18n.t("reviews.desc.stopped_supplier", supplier: reviewable.name) if stopped? && reviewable.is_a?(Supplier)
    return I18n.t("reviews.desc.stopped", folio: reviewable.to_s) if stopped?
    case reviewable
    when Movement then I18n.t("reviews.desc.movement", kind: reviewable.kind_name, quantity: quantity_of(reviewable))
    when Withdrawal then I18n.t("reviews.desc.withdrawal", amount: Money.format_money(reviewable.amount_cents), folio: reviewable.shift.folio)
    when SupplierInvoice then I18n.t("reviews.desc.supplier_invoice", folio: reviewable.folio, supplier: reviewable.supplier.name)
    when Receipt then I18n.t("reviews.desc.receipt", folio: reviewable.folio, supplier: reviewable.supplier.name)
    when Sale then I18n.t("reviews.desc.sale", folio: reviewable.folio, total: Money.format_money(reviewable.total_cents))
    when Shift
      return I18n.t("reviews.desc.open_shift", folio: reviewable.folio) if reviewable.open?
      I18n.t("reviews.desc.shift", folio: reviewable.folio, difference: Money.format_money(reviewable.difference_cents))
    when SaleLine
      I18n.t("reviews.desc.sale_line", folio: reviewable.sale.folio, product: reviewable.product.name, price: Money.format_money(reviewable.price_cents), catalog: Money.format_money(reviewable.catalog_cents))
    else "#{reviewable_type} #{reviewable_id}"
    end
  end

  private

  def resolve!(new_status, user:, note:)
    raise ArgumentError, I18n.t("errors.review.already", status: I18n.t("statuses.#{status}")) unless pending?
    update!(status: new_status, reviewed_by: user, reviewed_at: Time.current, note: note)
  end

  def quantity_of(record)
    product = record.product
    "#{ActiveSupport::NumberHelper.number_to_rounded(record.quantity, precision: product.decimals)} #{product.unit} #{product.name}"
  end
end
