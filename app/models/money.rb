# Money in whole cents; conversions and formatting live here. The business sets the currency
# symbol in Settings (business.symbol).
module Money
  def self.cents(amount)
    return 0 if amount.blank?
    (BigDecimal(amount.to_s) * 100).round.to_i
  end

  def self.format_money(cents)
    negative = cents.to_i.negative?
    integer, dec = cents.to_i.abs.divmod(100)
    "#{negative ? '−' : ''}#{Setting.symbol}#{integer.to_s.reverse.scan(/\d{1,3}/).join(',').reverse}.#{dec.to_s.rjust(2, '0')}"
  end

  # A line's amount: quantity × unit price, rounded to cents.
  def self.amount(quantity, price_cents)
    (BigDecimal(quantity.to_s) * price_cents).round.to_i
  end
end
