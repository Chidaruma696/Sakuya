# What open customer orders have reserved and what is left available. Selling and stock transfers
# respect reservations; waste and adjustments do not, because they record something that already happened.
module Reservations
  class Error < ArgumentError; end

  # { product_id => reserved quantity } at a branch, leaving out one order (the one being checked out).
  def self.by_product(branch, except: nil)
    return {} unless Features.active?("customers")
    lines = OrderLine.joins(:order).where(orders: { branch_id: branch.id, status: "open", reserve: true })
    lines = lines.where.not(order_id: except.id) if except
    lines.group(:product_id).sum(:quantity)
  end

  def self.reserved_for(branch, product, except: nil) = by_product(branch, except: except).fetch(product.id, BigDecimal("0"))

  def self.available(branch, product, except: nil) = StockLevel.quantity_for(branch, product) - reserved_for(branch, product, except: except)

  # Makes sure what goes out ([[product, quantity]]) does not eat into reservations. If there is
  # not enough for another reason (no stock), the kardex says so when moving it.
  def self.check!(branch, outflows, except: nil)
    reservations = by_product(branch, except: except)
    return if reservations.empty?
    outflows.group_by(&:first).each do |product, rows|
      quantity = rows.sum(&:last)
      on_hand = StockLevel.quantity_for(branch, product)
      reserved = reservations.fetch(product.id, 0)
      next if reserved.zero? || quantity <= on_hand - reserved || quantity > on_hand
      qty = ->(v) { ApplicationController.helpers.quantity(v, product) }
      raise Error, I18n.t("errors.reserved.not_enough", product: product.name, on_hand: qty.(on_hand), reserved: qty.(reserved), available: qty.(on_hand - reserved))
    end
  end
end
