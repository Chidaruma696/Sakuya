# The only door for changing stock levels: writes the movement and updates the projection in
# the same transaction. Rails opens SQLite transactions in IMMEDIATE mode, so two tills cannot
# read the same balance at once; in PostgreSQL the row lock guarantees it.
module Inventory
  class OutOfStock < StandardError; end

  def self.move!(branch:, product:, kind:, quantity:, user:, reference: nil, reason: nil, date: Date.current)
    quantity = BigDecimal(quantity.to_s).round(3)
    raise ArgumentError, I18n.t("errors.inventory.zero_quantity") unless quantity.positive?
    delta = Movement.sign(kind) * quantity

    Movement.transaction do
      stock_level = StockLevel.lock.find_or_create_by!(branch: branch, product: product)
      balance = stock_level.quantity + delta
      if balance.negative?
        raise OutOfStock, I18n.t("errors.inventory.insufficient", product: product.name, branch: branch.name, on_hand: stock_level.quantity.to_s("F"), requested: quantity.to_s("F"))
      end
      stock_level.update!(quantity: balance)
      Movement.create!(branch: branch, product: product, kind: kind, quantity: quantity, balance: balance,
                         reference: reference, user: user, reason: reason, business_date: date)
    end
  end
end
