# What is known about a customer's account, for the credit rule and for their statement.
# Payments settle the oldest charges first; whatever is left over from a payment stays as credit.
class CustomerAccount
  attr_reader :customer

  def initialize(customer, today: Date.current)
    @customer = customer
    @today = today
  end

  def movements = @movements ||= customer.credit_movements.in_order.to_a
  def balance_cents = movements.sum(&:amount_cents)

  # What is owed on charges older than `days` days.
  def overdue_cents(days) = open_charges.select { |date, _| (@today - date).to_i > days }.sum { |_, remaining| remaining }

  # Days since the last payment; nil if they never paid.
  def days_since_payment
    last = movements.select { |m| m.kind == "account_payment" }.map(&:date).max
    last && (@today - last).to_i
  end

  # What is owed by age of the charge: { "0-30" => cents, "31-60" => …, "61-90" => …, "90+" => … }.
  def age
    buckets = { "0-30" => 0, "31-60" => 0, "61-90" => 0, "90+" => 0 }
    open_charges.each do |date, remaining|
      days = (@today - date).to_i
      buckets[days <= 30 ? "0-30" : days <= 60 ? "31-60" : days <= 90 ? "61-90" : "90+"] += remaining
    end
    buckets
  end

  # [[date, what is left]] for each unpaid charge.
  def open_charges
    @open_charges ||= begin
      charges = []
      in_favor = 0
      movements.each do |m|
        if m.amount_cents.positive?
          used = [ in_favor, m.amount_cents ].min
          in_favor -= used
          charges << [ m.date, m.amount_cents - used ] if m.amount_cents > used
        else
          remaining = -m.amount_cents
          charges.each do |c|
            break if remaining.zero?
            applies = [ c[1], remaining ].min
            c[1] -= applies
            remaining -= applies
          end
          in_favor += remaining
        end
      end
      charges.select { |c| c[1].positive? }
    end
  end
end
