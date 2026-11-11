# Returnable containers (crates, bottles…): the ledger of pieces per customer and kind, what each
# returnable product releases, and a write-off charged to the customer's account.
class AddReturnables < ActiveRecord::Migration[8.1]
  def change
    # Insert only. quantity is signed: above zero the pieces left with the customer, below zero they
    # came back, were written off or were entered in the customer's favor. kind is a key declared
    # in the returnables rule.
    create_table :returnable_movements do |t|
      t.integer :customer_id, null: false
      t.string :kind, null: false
      t.integer :quantity, null: false
      t.string :reason, null: false
      t.string :note
      t.date :date, null: false
      t.integer :branch_id, null: false
      t.integer :user_id, null: false
      t.integer :reference_id
      t.string :reference_type
      t.string :key
      t.datetime :created_at, null: false
      t.index %i[customer_id kind date id], name: "index_returnable_movements_on_customer_kind_date"
      t.index %i[reference_type reference_id], name: "index_returnable_movements_on_reference"
      t.index :key, unique: true, where: "key IS NOT NULL"
      t.check_constraint "quantity <> 0", name: "returnable_movements_quantity"
      t.check_constraint "reason IN ('out', 'back', 'write_off', 'entry')", name: "returnable_movements_reason"
    end

    # What a returnable product releases: which kind, from what quantity on a ticket line, and one
    # piece per every how many units (blank = one piece per line that reaches the quantity).
    create_table :product_returnables do |t|
      t.integer :product_id, null: false
      t.string :kind, null: false
      t.decimal :from_quantity, precision: 12, scale: 3, null: false
      t.decimal :per_quantity, precision: 12, scale: 3
      t.timestamps
      t.index %i[product_id kind], unique: true
      t.check_constraint "from_quantity > 0", name: "product_returnables_from"
      t.check_constraint "per_quantity IS NULL OR per_quantity > 0", name: "product_returnables_per"
    end
    add_column :products, :returnable, :boolean, default: false, null: false

    remove_check_constraint :credit_movements, "kind IN ('charge', 'account_payment', 'refund')", name: "credit_movements_kind"
    add_check_constraint :credit_movements, "kind IN ('charge', 'account_payment', 'refund', 'returnable')", name: "credit_movements_kind"
  end
end
