# What must never exist twice, enforced by the database itself: two requests arriving at the same
# moment (a double click, the same user on two screens) both pass any check written in Ruby.
class GuardAgainstDuplicates < ActiveRecord::Migration[8.1]
  def change
    # One open shift and one open stock count per branch.
    add_index :shifts, :branch_id, unique: true, where: "status = 'open'", name: "index_shifts_one_open_per_branch"
    add_index :stock_counts, :branch_id, unique: true, where: "status = 'open'", name: "index_stock_counts_one_open_per_branch"

    # The form's idempotency key, as sales, receipts and stock transfers already carry: sending
    # the same form twice records the money once.
    %i[withdrawals account_payments supplier_payments refunds].each do |table|
      add_column table, :key, :string
      add_index table, :key, unique: true, where: "key IS NOT NULL"
    end
  end
end
