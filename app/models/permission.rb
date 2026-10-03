# Permission keys. A role has a list of keys; "*" allows everything and "till.*" a whole feature.
module Permission
  KEYS = {
    "till.sell" => "Sell at the till",
    "till.open" => "Open and close the till",
    "till.withdraw" => "Move cash to the safe",
    "till.difference" => "Close the shift with a difference above the limit",
    "till.lower_price" => "Authorize a price below the catalog price",
    "till.force_sale" => "Check out a sale the sales rule stops (it goes to review)",
    "till.refund" => "Take customer refunds",
    "inventory.view" => "See stock levels and movements",
    "inventory.adjust" => "Adjust stock levels with a reason",
    "stock_counts.make" => "Do physical stock counts and charge shortages",
    "stock_counts.charges" => "Collect or forgive charges",
    "reports.view" => "See the dashboard and the reports",
    "reviews.resolve" => "Review what was done without authorization (approve, flag, charge)",
    "customers.view" => "See customers",
    "customers.edit" => "Add and edit customers",
    "customers.orders" => "Take and cancel customer orders",
    "customers.pay_account" => "Take customer account payments at the till",
    "customers.force_credit" => "Sell on account even if the credit rule stops it (it goes to review)",
    "purchases.view" => "See suppliers and accounts payable",
    "purchases.receive" => "Receive goods from suppliers",
    "purchases.invoice" => "Enter and cancel supplier invoices",
    "purchases.pay" => "Pay suppliers from the till",
    "purchases.force_receipt" => "Receive goods the receipts rule stops (it goes to review)",
    "purchases.exceed" => "Record an invoice with more than was received (with a reason, it goes to review)",
    "warehouses.transfer_stock" => "Bulk stock transfers between branches and warehouses",
    "admin.catalog" => "Manage products and barcodes",
    "admin.users" => "Manage users, roles and branches",
    "rules.edit" => "Write the business's Lisp programs (the dashboard)"
  }.freeze

  FEATURES = KEYS.keys.map { |c| c.split(".").first }.uniq.freeze

  # Display name, in the user's language (permissions.* in config/locales).
  def self.name(key)
    # The key contains a dot, so "permissions.till.sell" cannot be looked up directly (I18n would nest it).
    I18n.t("permissions", default: {})[key.to_sym] || KEYS[key]
  end

  def self.valid?(key)
    key == "*" || KEYS.key?(key) || (key.end_with?(".*") && FEATURES.include?(key.delete_suffix(".*")))
  end

  # Does a role's list of keys cover this key?
  def self.covers?(permissions, key)
    return false unless KEYS.key?(key)
    feature = key.split(".").first
    permissions.include?("*") || permissions.include?(key) || permissions.include?("#{feature}.*")
  end
end
