# A question asked of the REPL: who, from which branch, what they typed and whether it ran. Insert only.
class ReplQuery < ApplicationRecord
  self.table_name = "repl_queries"

  belongs_to :user
  belongs_to :branch

  validates :text, presence: true

  before_update { raise ActiveRecord::ReadOnlyRecord, "the REPL log cannot be edited" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "the REPL log cannot be deleted" }
end
