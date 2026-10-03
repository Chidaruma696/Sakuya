class Role < ApplicationRecord
  has_many :users, dependent: :restrict_with_error

  # The roles the system starts with; the administrator can do everything. They can be edited later.
  # Out of the box each role has just what it needs: refunding money or receiving goods belongs to a
  # supervisor or the warehouse, not the till.
  BASE = {
    "administrator" => [ "*" ],
    "cashier" => [ "till.sell", "till.open", "till.withdraw", "inventory.view", "customers.view", "customers.pay_account", "customers.orders" ],
    "warehouse_keeper" => [ "inventory.view", "purchases.receive", "warehouses.transfer_stock", "stock_counts.make" ],
    "supervisor" => [ "till.*", "inventory.*", "purchases.*", "warehouses.*", "stock_counts.*", "customers.*", "reports.view", "reviews.resolve" ]
  }.freeze

  validates :name, presence: true, uniqueness: true
  validate :known_permissions

  def self.base!
    BASE.each { |name, permissions| find_or_initialize_by(name: name).update!(permissions: permissions) }
  end

  def allows?(key)
    Permission.covers?(permissions, key)
  end

  def to_s
    name
  end

  private

  def known_permissions
    return errors.add(:permissions, I18n.t("errors.role.list")) unless permissions.is_a?(Array)
    unknown = permissions.reject { |k| Permission.valid?(k) }
    errors.add(:permissions, I18n.t("errors.role.unknown", keys: unknown.join(", "))) if unknown.any?
  end
end
