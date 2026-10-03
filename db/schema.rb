# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_03_100000) do
  create_table "account_payments", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "branch_id", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.string "folio", null: false
    t.string "notes"
    t.string "payment_method", null: false
    t.integer "shift_id", null: false
    t.integer "user_id", null: false
    t.index ["branch_id", "folio"], name: "index_account_payments_on_branch_id_and_folio", unique: true
    t.index ["branch_id"], name: "index_account_payments_on_branch_id"
    t.index ["customer_id"], name: "index_account_payments_on_customer_id"
    t.index ["shift_id"], name: "index_account_payments_on_shift_id"
    t.index ["user_id"], name: "index_account_payments_on_user_id"
    t.check_constraint "amount_cents > 0", name: "account_payments_amount"
    t.check_constraint "payment_method IN ('cash', 'transfer', 'deposit')", name: "account_payments_payment_method"
  end

  create_table "branch_prices", force: :cascade do |t|
    t.integer "branch_id", null: false
    t.datetime "created_at", null: false
    t.integer "price_cents", null: false
    t.integer "product_id", null: false
    t.datetime "updated_at", null: false
    t.index ["branch_id"], name: "index_branch_prices_on_branch_id"
    t.index ["product_id", "branch_id"], name: "index_branch_prices_on_product_id_and_branch_id", unique: true
    t.index ["product_id"], name: "index_branch_prices_on_product_id"
    t.check_constraint "price_cents >= 0", name: "branch_prices_no_negative"
  end

  create_table "branches", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "cash_limit_cents", default: 300000, null: false
    t.string "code", null: false
    t.integer "count_interval_days"
    t.datetime "created_at", null: false
    t.string "kind", default: "store", null: false
    t.string "name", null: false
    t.string "network_printer"
    t.string "printer", default: "browser", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_branches_on_code", unique: true
    t.check_constraint "kind IN ('head_office', 'store', 'warehouse')", name: "branches_kind"
  end

  create_table "charges", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "branch_id", null: false
    t.datetime "created_at", null: false
    t.text "detail"
    t.datetime "resolved_at"
    t.integer "resolved_by_id"
    t.integer "review_id"
    t.string "status", default: "pending", null: false
    t.integer "stock_count_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["branch_id"], name: "index_charges_on_branch_id"
    t.index ["resolved_by_id"], name: "index_charges_on_resolved_by_id"
    t.index ["review_id"], name: "index_charges_on_review_id"
    t.index ["stock_count_id"], name: "index_charges_on_stock_count_id"
    t.index ["user_id"], name: "index_charges_on_user_id"
    t.check_constraint "amount_cents > 0", name: "charges_amount"
    t.check_constraint "status IN ('pending', 'paid', 'forgiven')", name: "charges_status"
  end

  create_table "counters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.integer "last", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_counters_on_key", unique: true
  end

  create_table "credit_movements", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "branch_id", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.date "date", null: false
    t.string "kind", null: false
    t.string "reason"
    t.integer "reference_id"
    t.string "reference_type"
    t.integer "user_id", null: false
    t.index ["branch_id"], name: "index_credit_movements_on_branch_id"
    t.index ["customer_id", "date", "id"], name: "index_credit_movements_on_customer_id_and_date_and_id"
    t.index ["customer_id"], name: "index_credit_movements_on_customer_id"
    t.index ["reference_type", "reference_id"], name: "index_credit_movements_on_reference"
    t.index ["user_id"], name: "index_credit_movements_on_user_id"
    t.check_constraint "kind IN ('charge', 'account_payment', 'refund')", name: "credit_movements_kind"
  end

  create_table "customers", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "address"
    t.datetime "created_at", null: false
    t.integer "credit_limit_cents", default: 0, null: false
    t.string "name", null: false
    t.string "notes"
    t.string "phone"
    t.string "tax_id"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_customers_on_name"
  end

  create_table "folios", force: :cascade do |t|
    t.integer "branch_id", null: false
    t.datetime "created_at", null: false
    t.integer "last", default: 0, null: false
    t.string "prefix", null: false
    t.datetime "updated_at", null: false
    t.index ["branch_id", "prefix"], name: "index_folios_on_branch_id_and_prefix", unique: true
    t.index ["branch_id"], name: "index_folios_on_branch_id"
  end

  create_table "minimums", force: :cascade do |t|
    t.integer "branch_id", null: false
    t.datetime "created_at", null: false
    t.decimal "maximum", precision: 12, scale: 3
    t.decimal "minimum", precision: 12, scale: 3, null: false
    t.integer "product_id", null: false
    t.datetime "updated_at", null: false
    t.index ["branch_id", "product_id"], name: "index_minimums_on_branch_id_and_product_id", unique: true
    t.index ["branch_id"], name: "index_minimums_on_branch_id"
    t.index ["product_id"], name: "index_minimums_on_product_id"
    t.check_constraint "maximum IS NULL OR maximum >= minimum", name: "minimums_maximum"
    t.check_constraint "minimum >= 0", name: "minimums_minimum"
  end

  create_table "movements", force: :cascade do |t|
    t.decimal "balance", precision: 12, scale: 3, null: false
    t.integer "branch_id", null: false
    t.date "business_date", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.integer "product_id", null: false
    t.decimal "quantity", precision: 12, scale: 3, null: false
    t.string "reason"
    t.integer "reference_id"
    t.string "reference_type"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["branch_id", "business_date"], name: "index_movements_on_branch_id_and_business_date"
    t.index ["branch_id", "product_id", "created_at"], name: "idx_on_branch_id_product_id_created_at_be784bb004"
    t.index ["branch_id"], name: "index_movements_on_branch_id"
    t.index ["product_id"], name: "index_movements_on_product_id"
    t.index ["reference_type", "reference_id"], name: "index_movements_on_reference"
    t.index ["user_id"], name: "index_movements_on_user_id"
    t.check_constraint "kind IN ('inflow', 'receipt', 'customer_return', 'adjustment_inflow', 'sale', 'outflow', 'waste', 'adjustment_outflow')", name: "movements_kind"
    t.check_constraint "quantity > 0", name: "movements_quantity_positive"
  end

  create_table "order_lines", force: :cascade do |t|
    t.integer "order_id", null: false
    t.integer "product_id", null: false
    t.decimal "quantity", precision: 12, scale: 3, null: false
    t.index ["order_id"], name: "index_order_lines_on_order_id"
    t.index ["product_id"], name: "index_order_lines_on_product_id"
    t.check_constraint "quantity > 0", name: "order_lines_quantity"
  end

  create_table "orders", force: :cascade do |t|
    t.integer "branch_id", null: false
    t.string "cancellation_reason"
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.date "delivery_date"
    t.string "folio", null: false
    t.string "notes"
    t.boolean "reserve", default: true, null: false
    t.integer "sale_id"
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["branch_id", "folio"], name: "index_orders_on_branch_id_and_folio", unique: true
    t.index ["branch_id"], name: "index_orders_on_branch_id"
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["sale_id"], name: "index_orders_on_sale_id"
    t.index ["user_id"], name: "index_orders_on_user_id"
    t.check_constraint "status IN ('open', 'delivered', 'cancelled')", name: "orders_status"
  end

  create_table "payments", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "payment_method", null: false
    t.integer "sale_id", null: false
    t.datetime "updated_at", null: false
    t.index ["sale_id"], name: "index_payments_on_sale_id"
    t.check_constraint "amount_cents > 0", name: "payments_amount"
    t.check_constraint "payment_method IN ('cash', 'transfer', 'deposit', 'credit')", name: "payments_payment_method"
  end

  create_table "plugins", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.string "author"
    t.text "code", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.string "identifier", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "version"
    t.index ["identifier"], name: "index_plugins_on_identifier", unique: true
    t.index ["user_id"], name: "index_plugins_on_user_id"
  end

  create_table "product_barcodes", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.integer "product_id", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_product_barcodes_on_code", unique: true
    t.index ["product_id"], name: "index_product_barcodes_on_product_id"
  end

  create_table "products", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "line"
    t.string "name", null: false
    t.integer "plu", null: false
    t.integer "price_cents", default: 0, null: false
    t.string "unit", default: "kg", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_products_on_key", unique: true
    t.index ["plu"], name: "index_products_on_plu", unique: true
    t.check_constraint "plu BETWEEN 1 AND 99999", name: "products_plu_range"
    t.check_constraint "price_cents >= 0", name: "products_price_no_negative"
    t.check_constraint "unit IN ('kg', 'piece', 'liter', 'meter')", name: "products_unit"
  end

  create_table "promotions", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "branch_id"
    t.datetime "created_at", null: false
    t.date "from"
    t.string "kind", null: false
    t.decimal "minimum_quantity", precision: 12, scale: 3, default: "0.0", null: false
    t.string "name", null: false
    t.decimal "percentage", precision: 5, scale: 2
    t.integer "price_cents"
    t.integer "product_id", null: false
    t.date "to"
    t.datetime "updated_at", null: false
    t.index ["branch_id"], name: "index_promotions_on_branch_id"
    t.index ["product_id", "active"], name: "index_promotions_on_product_id_and_active"
    t.index ["product_id"], name: "index_promotions_on_product_id"
    t.check_constraint "kind IN ('price', 'percentage', 'by_quantity')", name: "promotions_kind"
  end

  create_table "receipt_lines", force: :cascade do |t|
    t.integer "boxes", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "product_id", null: false
    t.decimal "quantity", precision: 12, scale: 3, null: false
    t.integer "receipt_id", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_receipt_lines_on_product_id"
    t.index ["receipt_id"], name: "index_receipt_lines_on_receipt_id"
  end

  create_table "receipts", force: :cascade do |t|
    t.integer "branch_id", null: false
    t.string "cancellation_reason"
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.string "delivery_note"
    t.string "folio", null: false
    t.string "key"
    t.string "notes"
    t.string "status", default: "registered", null: false
    t.integer "supplier_id", null: false
    t.integer "supplier_invoice_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["branch_id", "folio"], name: "index_receipts_on_branch_id_and_folio", unique: true
    t.index ["branch_id", "key"], name: "index_receipts_on_branch_id_and_key", unique: true, where: "key IS NOT NULL"
    t.index ["branch_id"], name: "index_receipts_on_branch_id"
    t.index ["supplier_id"], name: "index_receipts_on_supplier_id"
    t.index ["supplier_invoice_id"], name: "index_receipts_on_supplier_invoice_id"
    t.index ["user_id"], name: "index_receipts_on_user_id"
    t.check_constraint "status IN ('registered', 'cancelled')", name: "receipts_status"
  end

  create_table "refund_lines", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.decimal "quantity", precision: 12, scale: 3, null: false
    t.integer "refund_id", null: false
    t.integer "sale_line_id", null: false
    t.datetime "updated_at", null: false
    t.index ["refund_id"], name: "index_refund_lines_on_refund_id"
    t.index ["sale_line_id"], name: "index_refund_lines_on_sale_line_id"
    t.check_constraint "quantity > 0", name: "refund_lines_quantity"
  end

  create_table "refunds", force: :cascade do |t|
    t.integer "branch_id", null: false
    t.datetime "created_at", null: false
    t.string "folio", null: false
    t.integer "on_account_cents", default: 0, null: false
    t.string "reason", null: false
    t.integer "sale_id", null: false
    t.integer "shift_id"
    t.integer "total_cents", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["branch_id", "folio"], name: "index_refunds_on_branch_and_folio", unique: true
    t.index ["branch_id"], name: "index_refunds_on_branch_id"
    t.index ["sale_id"], name: "index_refunds_on_sale_id"
    t.index ["shift_id"], name: "index_refunds_on_shift_id"
    t.index ["user_id"], name: "index_refunds_on_user_id"
  end

  create_table "repl_queries", force: :cascade do |t|
    t.integer "branch_id", null: false
    t.datetime "created_at", null: false
    t.boolean "ok", null: false
    t.text "text", null: false
    t.integer "user_id", null: false
    t.index ["branch_id"], name: "index_repl_queries_on_branch_id"
    t.index ["created_at"], name: "index_repl_queries_on_created_at"
    t.index ["user_id"], name: "index_repl_queries_on_user_id"
  end

  create_table "reviews", force: :cascade do |t|
    t.integer "branch_id", null: false
    t.datetime "created_at", null: false
    t.string "note"
    t.string "reason", null: false
    t.integer "reviewable_id", null: false
    t.string "reviewable_type", null: false
    t.datetime "reviewed_at"
    t.integer "reviewed_by_id"
    t.string "status", default: "pending", null: false
    t.boolean "stopped", default: false, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "value_cents", default: 0, null: false
    t.index ["branch_id", "status"], name: "index_reviews_on_branch_id_and_status"
    t.index ["branch_id"], name: "index_reviews_on_branch_id"
    t.index ["reviewable_type", "reviewable_id"], name: "index_reviews_on_reviewable"
    t.index ["reviewed_by_id"], name: "index_reviews_on_reviewed_by_id"
    t.index ["user_id"], name: "index_reviews_on_user_id"
    t.check_constraint "status IN ('pending', 'approved', 'flagged')", name: "reviews_status"
  end

  create_table "roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.json "permissions", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_roles_on_name", unique: true
  end

  create_table "rules", force: :cascade do |t|
    t.text "code", null: false
    t.datetime "created_at", null: false
    t.string "hook", null: false
    t.integer "user_id", null: false
    t.integer "version", default: 1, null: false
    t.index ["hook", "id"], name: "index_rules_on_hook_and_id"
    t.index ["user_id"], name: "index_rules_on_user_id"
  end

  create_table "sale_lines", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "authorized_by_id"
    t.integer "catalog_cents", null: false
    t.datetime "created_at", null: false
    t.integer "price_cents", null: false
    t.integer "product_id", null: false
    t.integer "promotion_id"
    t.decimal "quantity", precision: 12, scale: 3, null: false
    t.integer "sale_id", null: false
    t.datetime "updated_at", null: false
    t.index ["authorized_by_id"], name: "index_sale_lines_on_authorized_by_id"
    t.index ["product_id"], name: "index_sale_lines_on_product_id"
    t.index ["promotion_id"], name: "index_sale_lines_on_promotion_id"
    t.index ["sale_id"], name: "index_sale_lines_on_sale_id"
    t.check_constraint "price_cents >= 0 AND amount_cents >= 0", name: "sale_lines_money"
    t.check_constraint "quantity > 0", name: "sale_lines_quantity"
  end

  create_table "sales", force: :cascade do |t|
    t.integer "branch_id", null: false
    t.date "business_date", null: false
    t.integer "change_cents", default: 0, null: false
    t.string "code", limit: 13, null: false
    t.datetime "created_at", null: false
    t.integer "customer_id"
    t.string "folio", null: false
    t.string "key", null: false
    t.boolean "offline", default: false, null: false
    t.integer "shift_id", null: false
    t.datetime "sold_at"
    t.string "status", default: "paid", null: false
    t.integer "total_cents", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["branch_id", "folio"], name: "index_sales_on_branch_and_folio", unique: true
    t.index ["branch_id"], name: "index_sales_on_branch_id"
    t.index ["code"], name: "index_sales_on_code", unique: true
    t.index ["customer_id"], name: "index_sales_on_customer_id"
    t.index ["key"], name: "index_sales_on_key", unique: true
    t.index ["shift_id", "status"], name: "index_sales_on_shift_id_and_status"
    t.index ["shift_id"], name: "index_sales_on_shift_id"
    t.index ["user_id"], name: "index_sales_on_user_id"
    t.check_constraint "status IN ('paid', 'refunded')", name: "sales_status"
    t.check_constraint "total_cents >= 0", name: "sales_total"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "shifts", force: :cascade do |t|
    t.integer "branch_id", null: false
    t.text "breakdown"
    t.datetime "closed_at"
    t.integer "closed_by_id"
    t.integer "counted_cents"
    t.datetime "created_at", null: false
    t.integer "difference_cents"
    t.integer "expected_cents"
    t.integer "float_cents", default: 0, null: false
    t.string "folio", null: false
    t.datetime "opened_at", null: false
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["branch_id", "folio"], name: "index_shifts_on_branch_and_folio", unique: true
    t.index ["branch_id", "status"], name: "index_shifts_on_branch_id_and_status"
    t.index ["branch_id"], name: "index_shifts_on_branch_id"
    t.index ["closed_by_id"], name: "index_shifts_on_closed_by_id"
    t.index ["user_id"], name: "index_shifts_on_user_id"
    t.check_constraint "float_cents >= 0", name: "shifts_float"
    t.check_constraint "status IN ('open', 'closed')", name: "shifts_status"
  end

  create_table "stock_count_lines", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "difference", precision: 12, scale: 3
    t.integer "difference_cents"
    t.decimal "manual", precision: 12, scale: 3, default: "0.0", null: false
    t.integer "product_id", null: false
    t.decimal "scanned", precision: 12, scale: 3, default: "0.0", null: false
    t.integer "stock_count_id", null: false
    t.decimal "system", precision: 12, scale: 3, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_stock_count_lines_on_product_id"
    t.index ["stock_count_id", "product_id"], name: "index_stock_count_lines_on_stock_count_id_and_product_id", unique: true
    t.index ["stock_count_id"], name: "index_stock_count_lines_on_stock_count_id"
  end

  create_table "stock_counts", force: :cascade do |t|
    t.integer "branch_id", null: false
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.string "folio", null: false
    t.text "notes"
    t.integer "responsible_id", null: false
    t.string "scope", default: "total", null: false
    t.integer "shortage_cents"
    t.string "status", default: "open", null: false
    t.integer "surplus_cents"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["branch_id", "folio"], name: "index_stock_counts_on_branch_and_folio", unique: true
    t.index ["branch_id", "status"], name: "index_stock_counts_on_branch_id_and_status"
    t.index ["branch_id"], name: "index_stock_counts_on_branch_id"
    t.index ["responsible_id"], name: "index_stock_counts_on_responsible_id"
    t.index ["user_id"], name: "index_stock_counts_on_user_id"
    t.check_constraint "status IN ('open', 'closed')", name: "stock_counts_status"
  end

  create_table "stock_levels", force: :cascade do |t|
    t.integer "branch_id", null: false
    t.datetime "created_at", null: false
    t.integer "product_id", null: false
    t.decimal "quantity", precision: 12, scale: 3, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["branch_id", "product_id"], name: "index_stock_levels_on_branch_id_and_product_id", unique: true
    t.index ["branch_id"], name: "index_stock_levels_on_branch_id"
    t.index ["product_id"], name: "index_stock_levels_on_product_id"
    t.check_constraint "quantity >= 0", name: "stock_levels_no_negative"
  end

  create_table "stock_transfer_lines", force: :cascade do |t|
    t.integer "boxes", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "product_id", null: false
    t.decimal "quantity", precision: 12, scale: 3, null: false
    t.integer "stock_transfer_id", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_stock_transfer_lines_on_product_id"
    t.index ["stock_transfer_id"], name: "index_stock_transfer_lines_on_stock_transfer_id"
  end

  create_table "stock_transfers", force: :cascade do |t|
    t.string "cancellation_reason"
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.integer "destination_branch_id", null: false
    t.string "folio", null: false
    t.string "key"
    t.string "notes"
    t.integer "origin_branch_id", null: false
    t.string "status", default: "registered", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["destination_branch_id"], name: "index_stock_transfers_on_destination_branch_id"
    t.index ["origin_branch_id", "folio"], name: "index_stock_transfers_on_origin_branch_id_and_folio", unique: true
    t.index ["origin_branch_id", "key"], name: "index_stock_transfers_on_origin_branch_id_and_key", unique: true, where: "key IS NOT NULL"
    t.index ["origin_branch_id"], name: "index_stock_transfers_on_origin_branch_id"
    t.index ["user_id"], name: "index_stock_transfers_on_user_id"
    t.check_constraint "status IN ('registered', 'cancelled')", name: "stock_transfers_status"
  end

  create_table "supplier_invoice_lines", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "boxes", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "price_cents", null: false
    t.integer "product_id", null: false
    t.decimal "quantity", precision: 12, scale: 3, null: false
    t.integer "supplier_invoice_id", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_supplier_invoice_lines_on_product_id"
    t.index ["supplier_invoice_id"], name: "index_supplier_invoice_lines_on_supplier_invoice_id"
  end

  create_table "supplier_invoices", force: :cascade do |t|
    t.integer "amount_cents", default: 0, null: false
    t.integer "branch_id", null: false
    t.string "cancellation_reason"
    t.string "concept"
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.date "due"
    t.string "folio", null: false
    t.string "status", default: "open", null: false
    t.integer "supplier_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["branch_id"], name: "index_supplier_invoices_on_branch_id"
    t.index ["supplier_id", "folio"], name: "index_supplier_invoices_on_supplier_id_and_folio", unique: true
    t.index ["supplier_id"], name: "index_supplier_invoices_on_supplier_id"
    t.index ["user_id"], name: "index_supplier_invoices_on_user_id"
    t.check_constraint "status IN ('open', 'cancelled')", name: "supplier_invoices_status"
  end

  create_table "supplier_movements", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "balance_cents", null: false
    t.integer "branch_id", null: false
    t.string "concept"
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.integer "delta_cents", null: false
    t.string "kind", null: false
    t.integer "supplier_id", null: false
    t.integer "supplier_invoice_id"
    t.integer "supplier_payment_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["branch_id"], name: "index_supplier_movements_on_branch_id"
    t.index ["supplier_id"], name: "index_supplier_movements_on_supplier_id"
    t.index ["supplier_invoice_id"], name: "index_supplier_movements_on_supplier_invoice_id"
    t.index ["supplier_payment_id"], name: "index_supplier_movements_on_supplier_payment_id"
    t.index ["user_id"], name: "index_supplier_movements_on_user_id"
    t.check_constraint "kind IN ('charge', 'payment', 'adjustment')", name: "supplier_movements_kind"
  end

  create_table "supplier_payments", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "branch_id", null: false
    t.datetime "created_at", null: false
    t.string "payment_method", default: "cash", null: false
    t.string "reference"
    t.integer "shift_id"
    t.string "status", default: "current", null: false
    t.integer "supplier_id", null: false
    t.integer "supplier_invoice_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "void_reason"
    t.integer "voided_by_id"
    t.integer "withdrawal_id"
    t.index ["branch_id"], name: "index_supplier_payments_on_branch_id"
    t.index ["shift_id"], name: "index_supplier_payments_on_shift_id"
    t.index ["supplier_id"], name: "index_supplier_payments_on_supplier_id"
    t.index ["supplier_invoice_id"], name: "index_supplier_payments_on_supplier_invoice_id"
    t.index ["user_id"], name: "index_supplier_payments_on_user_id"
    t.index ["voided_by_id"], name: "index_supplier_payments_on_voided_by_id"
    t.index ["withdrawal_id"], name: "index_supplier_payments_on_withdrawal_id"
    t.check_constraint "status IN ('current', 'voided')", name: "supplier_payments_status"
  end

  create_table "suppliers", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "contact"
    t.datetime "created_at", null: false
    t.integer "credit_days", default: 0, null: false
    t.string "name", null: false
    t.string "notes"
    t.string "phone"
    t.string "tax_id"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_suppliers_on_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "branch_id", null: false
    t.datetime "created_at", null: false
    t.string "density", default: "normal", null: false
    t.string "language", default: "en", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.integer "role_id", null: false
    t.string "text_size", default: "normal", null: false
    t.string "theme", default: "light", null: false
    t.datetime "updated_at", null: false
    t.string "user", null: false
    t.index ["branch_id"], name: "index_users_on_branch_id"
    t.index ["role_id"], name: "index_users_on_role_id"
    t.index ["user"], name: "index_users_on_user", unique: true
  end

  create_table "withdrawals", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "authorized_by_id"
    t.datetime "created_at", null: false
    t.string "reason", null: false
    t.integer "shift_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["authorized_by_id"], name: "index_withdrawals_on_authorized_by_id"
    t.index ["shift_id"], name: "index_withdrawals_on_shift_id"
    t.index ["user_id"], name: "index_withdrawals_on_user_id"
    t.check_constraint "amount_cents > 0", name: "withdrawals_amount"
  end

  add_foreign_key "account_payments", "branches"
  add_foreign_key "account_payments", "customers"
  add_foreign_key "account_payments", "shifts"
  add_foreign_key "account_payments", "users"
  add_foreign_key "branch_prices", "branches"
  add_foreign_key "branch_prices", "products"
  add_foreign_key "charges", "branches"
  add_foreign_key "charges", "reviews"
  add_foreign_key "charges", "stock_counts"
  add_foreign_key "charges", "users"
  add_foreign_key "charges", "users", column: "resolved_by_id"
  add_foreign_key "credit_movements", "branches"
  add_foreign_key "credit_movements", "customers"
  add_foreign_key "credit_movements", "users"
  add_foreign_key "folios", "branches"
  add_foreign_key "minimums", "branches"
  add_foreign_key "minimums", "products"
  add_foreign_key "movements", "branches"
  add_foreign_key "movements", "products"
  add_foreign_key "movements", "users"
  add_foreign_key "order_lines", "orders"
  add_foreign_key "order_lines", "products"
  add_foreign_key "orders", "branches"
  add_foreign_key "orders", "customers"
  add_foreign_key "orders", "sales"
  add_foreign_key "orders", "users"
  add_foreign_key "payments", "sales"
  add_foreign_key "plugins", "users"
  add_foreign_key "product_barcodes", "products"
  add_foreign_key "promotions", "branches"
  add_foreign_key "promotions", "products"
  add_foreign_key "receipt_lines", "products"
  add_foreign_key "receipt_lines", "receipts"
  add_foreign_key "receipts", "branches"
  add_foreign_key "receipts", "supplier_invoices"
  add_foreign_key "receipts", "suppliers"
  add_foreign_key "receipts", "users"
  add_foreign_key "refund_lines", "refunds"
  add_foreign_key "refund_lines", "sale_lines"
  add_foreign_key "refunds", "branches"
  add_foreign_key "refunds", "sales"
  add_foreign_key "refunds", "shifts"
  add_foreign_key "refunds", "users"
  add_foreign_key "repl_queries", "branches"
  add_foreign_key "repl_queries", "users"
  add_foreign_key "reviews", "branches"
  add_foreign_key "reviews", "users"
  add_foreign_key "reviews", "users", column: "reviewed_by_id"
  add_foreign_key "rules", "users"
  add_foreign_key "sale_lines", "products"
  add_foreign_key "sale_lines", "promotions"
  add_foreign_key "sale_lines", "sales"
  add_foreign_key "sale_lines", "users", column: "authorized_by_id"
  add_foreign_key "sales", "branches"
  add_foreign_key "sales", "customers"
  add_foreign_key "sales", "shifts"
  add_foreign_key "sales", "users"
  add_foreign_key "shifts", "branches"
  add_foreign_key "shifts", "users"
  add_foreign_key "shifts", "users", column: "closed_by_id"
  add_foreign_key "stock_count_lines", "products"
  add_foreign_key "stock_count_lines", "stock_counts"
  add_foreign_key "stock_counts", "branches"
  add_foreign_key "stock_counts", "users"
  add_foreign_key "stock_counts", "users", column: "responsible_id"
  add_foreign_key "stock_levels", "branches"
  add_foreign_key "stock_levels", "products"
  add_foreign_key "stock_transfer_lines", "products"
  add_foreign_key "stock_transfer_lines", "stock_transfers"
  add_foreign_key "stock_transfers", "branches", column: "destination_branch_id"
  add_foreign_key "stock_transfers", "branches", column: "origin_branch_id"
  add_foreign_key "stock_transfers", "users"
  add_foreign_key "supplier_invoice_lines", "products"
  add_foreign_key "supplier_invoice_lines", "supplier_invoices"
  add_foreign_key "supplier_invoices", "branches"
  add_foreign_key "supplier_invoices", "suppliers"
  add_foreign_key "supplier_invoices", "users"
  add_foreign_key "supplier_movements", "branches"
  add_foreign_key "supplier_movements", "supplier_invoices"
  add_foreign_key "supplier_movements", "supplier_payments"
  add_foreign_key "supplier_movements", "suppliers"
  add_foreign_key "supplier_movements", "users"
  add_foreign_key "supplier_payments", "branches"
  add_foreign_key "supplier_payments", "shifts"
  add_foreign_key "supplier_payments", "supplier_invoices"
  add_foreign_key "supplier_payments", "suppliers"
  add_foreign_key "supplier_payments", "users"
  add_foreign_key "supplier_payments", "users", column: "voided_by_id"
  add_foreign_key "supplier_payments", "withdrawals"
  add_foreign_key "users", "branches"
  add_foreign_key "users", "roles"
  add_foreign_key "withdrawals", "shifts"
  add_foreign_key "withdrawals", "users"
  add_foreign_key "withdrawals", "users", column: "authorized_by_id"
end
