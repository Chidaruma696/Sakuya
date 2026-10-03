# The Office-style ribbon: one tab per feature and, below, big buttons with the actions.
# Each button carries its text key (ribbon.buttons.*), the permission it needs and the name of
# its icon (Bootstrap Icons); a tab shows if any of its buttons shows.
module RibbonHelper
  Button = Struct.new(:key, :route, :permission, :icon)

  TABS = [
    { id: :home, groups: [
      { id: :view, buttons: [
        Button.new(:home, :root_path, nil, "house"),
        Button.new(:sales_by_product, :sales_by_product_path, "reports.view", "graph-up")
      ] },
      { id: :review, buttons: [ Button.new(:pending_review, :reviews_path, "reviews.resolve", "clipboard-check") ] },
      { id: :settings, buttons: [ Button.new(:settings, :settings_path, nil, "gear") ] }
    ] },
    { id: :till, groups: [
      { id: :sell, buttons: [
        Button.new(:sell, :till_path, "till.sell", "cart3"),
        Button.new(:sales, :till_sales_path, "till.sell", "receipt"),
        Button.new(:refund, :till_refund_path, "till.refund", "arrow-return-left")
      ] },
      { id: :shift, buttons: [ Button.new(:shift, :till_shift_path, "till.open", "cash-stack") ] }
    ] },
    { id: :inventory, groups: [
      { id: :query, buttons: [
        Button.new(:stock_levels, :inventory_path, "inventory.view", "list"),
        Button.new(:kardex, :kardex_inventory_path, "inventory.view", "arrow-down-up")
      ] },
      { id: :capture, buttons: [
        Button.new(:inflow_adjustment, :new_movement_inventory_path, "inventory.adjust", "pencil")
      ] }
    ] },
    { id: :purchases, groups: [
      { id: :receive, buttons: [
        Button.new(:receive, :new_receipt_path, "purchases.receive", "box-arrow-in-down"),
        Button.new(:receipts, :receipts_path, "purchases.view", "list-ul")
      ] },
      { id: :invoices, buttons: [
        Button.new(:new_invoice, :new_invoice_path, "purchases.invoice", "file-earmark-plus"),
        Button.new(:accounts_payable, :accounts_path, "purchases.view", "wallet2")
      ] },
      { id: :suppliers, buttons: [ Button.new(:suppliers, :suppliers_path, "purchases.view", "truck") ] }
    ] },
    { id: :customers, groups: [
      { id: :customers, buttons: [
        Button.new(:customers, :customers_path, "customers.view", "people"),
        Button.new(:new_customer, :new_customer_path, "customers.edit", "person-plus")
      ] },
      { id: :orders, buttons: [
        Button.new(:new_order, :new_order_path, "customers.orders", "journal-plus"),
        Button.new(:orders, :orders_path, "customers.view", "journal-text")
      ] }
    ] },
    { id: :warehouses, groups: [
      { id: :bulk, buttons: [
        Button.new(:stock_transfer_bulk, :new_stock_transfer_path, "warehouses.transfer_stock", "boxes"),
        Button.new(:stock_transfers, :stock_transfers_path, "warehouses.transfer_stock", "list-ul")
      ] },
      { id: :restock, buttons: [ Button.new(:restock, :restock_path, "warehouses.transfer_stock", "arrow-repeat") ] }
    ] },
    { id: :stock_counts, groups: [
      { id: :count, buttons: [
        Button.new(:new_stock_count, :new_stock_count_path, "stock_counts.make", "search"),
        Button.new(:stock_counts, :stock_counts_path, "stock_counts.make", "list-ul")
      ] },
      { id: :charges, buttons: [ Button.new(:charges, :charges_path, "stock_counts.charges", "cash-coin") ] }
    ] },
    { id: :admin, groups: [
      { id: :catalog, buttons: [
        Button.new(:products, :admin_products_path, "admin.catalog", "box-seam"),
        Button.new(:promotions, :admin_promotions_path, "admin.catalog", "percent")
      ] },
      { id: :people, buttons: [
        Button.new(:users, :admin_users_path, "admin.users", "person"),
        Button.new(:roles, :admin_roles_path, "admin.users", "key"),
        Button.new(:branches, :admin_branches_path, "admin.users", "shop")
      ] }
    ] }
  ].freeze

  def button_visible?(button)
    button.permission.nil? || can?(button.permission)
  end

  # A group can depend on one or several features.
  def group_visible?(group)
    Array(group[:feature]).all? { |m| Features.active?(m) } && group[:buttons].any? { |b| button_visible?(b) }
  end

  # A tab shows if its feature is on and any of its groups shows.
  def visible_tabs
    TABS.select do |tab|
      # A warehouse has no till and no stock counts: goods are only stored there.
      next false if %i[till stock_counts].include?(tab[:id]) && current_branch&.warehouse?
      Features.active?(tab[:id]) && tab[:groups].any? { |g| group_visible?(g) }
    end
  end

  # Settings hangs off Home in the ribbon; a controller whose tab is not listed falls back to Home.
  def active_tab
    TABS.find { |tab| tab[:id] == controller.ribbon_tab } || TABS.first
  end

  def route_of_tab(tab)
    button = tab[:groups].select { |g| group_visible?(g) }.flat_map { |g| g[:buttons] }.find { |b| button_visible?(b) }
    button ? send(button.route) : root_path
  end
end
