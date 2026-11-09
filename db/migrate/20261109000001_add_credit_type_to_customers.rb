# What a customer carries about credit besides their limit: the key of a credit type declared in
# the credit rule, and a weekly cut-off day (0 = Sunday … 6 = Saturday). Both optional.
class AddCreditTypeToCustomers < ActiveRecord::Migration[8.1]
  def change
    add_column :customers, :credit_type, :string
    add_column :customers, :cutoff_day, :integer
  end
end
