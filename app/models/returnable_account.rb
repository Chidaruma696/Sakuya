# What is known about the returnable containers a customer holds, for the returnables rule and
# for their account screen. Pieces that come back settle the oldest ones first; a customer who
# brought back more than they owed has pieces in their favor, and the next pieces that leave use
# those up before anything counts as out again.
class ReturnableAccount
  Count = Data.define(:kind, :owed, :in_favor, :oldest_days)

  attr_reader :customer

  def initialize(customer, today: Date.current)
    @customer = customer
    @today = today
  end

  def movements = @movements ||= customer.returnable_movements.in_order.to_a

  # The signed count of a kind: above zero they owe pieces, below zero they have them in their favor.
  def count(kind) = by_kind.fetch(kind.to_s, []).sum(&:quantity)
  def owed(kind) = [ count(kind), 0 ].max
  def in_favor(kind) = [ -count(kind), 0 ].max

  # Pieces of every kind they owe.
  def owed_all = by_kind.keys.sum { |kind| owed(kind) }

  # Age in days of the oldest piece of that kind still out; -1 if none.
  def oldest_days(kind)
    oldest = lots(kind).first
    oldest ? (@today - oldest.first).to_i : -1
  end

  # One Count per kind that ever moved, in the order they first did.
  def counts
    by_kind.keys.map { |kind| Count.new(kind: kind, owed: owed(kind), in_favor: in_favor(kind), oldest_days: oldest_days(kind)) }
  end

  # The signed count of every customer and kind at once, for lists: { customer_id => { "kind" => count } }.
  def self.all_counts
    ReturnableMovement.group(:customer_id, :kind).sum(:quantity).each_with_object({}) do |((customer_id, kind), count), all|
      (all[customer_id] ||= {})[kind] = count unless count.zero?
    end
  end

  private

  def by_kind = @by_kind ||= movements.group_by(&:kind)

  # [[date, pieces still out]] of a kind, oldest first.
  def lots(kind)
    out = []
    favor = 0
    by_kind.fetch(kind.to_s, []).each do |m|
      if m.quantity.positive?
        used = [ favor, m.quantity ].min
        favor -= used
        out << [ m.date, m.quantity - used ] if m.quantity > used
      else
        remaining = -m.quantity
        out.each do |lot|
          break if remaining.zero?
          applies = [ lot[1], remaining ].min
          lot[1] -= applies
          remaining -= applies
        end
        favor += remaining
      end
    end
    out.select { |lot| lot[1].positive? }
  end
end
