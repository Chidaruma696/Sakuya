class Counter < ApplicationRecord
  self.table_name = "counters"

  validates :key, presence: true, uniqueness: true

  # Next value of the sequence, atomically.
  def self.next_number!(key)
    transaction do
      c = find_or_create_by!(key: key)
      where(id: c.id).update_all("last = last + 1")
      c.reload.last
    end
  end

  # Like next_number!, but wraps around on reaching `maximum` (1..maximum).
  def self.next_cyclic!(key, maximum)
    ((next_number!(key) - 1) % maximum) + 1
  end
end
