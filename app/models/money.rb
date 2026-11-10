# Money in whole cents; conversions and formatting live here. The business sets the currency
# symbol in Settings (business.symbol).
module Money
  # What was typed is not an amount ("abc", "12,50"). The message is already in the user's language.
  class Invalid < ArgumentError; end

  LARGEST = 10**12 # in currency units; anything bigger is a slip of the keyboard

  def self.cents(amount)
    return 0 if amount.blank?
    value = begin
      BigDecimal(amount.to_s.strip)
    rescue ArgumentError
      nil
    end
    raise Invalid, I18n.t("errors.money.invalid", value: amount.to_s.strip.truncate(20)) unless value&.finite? && value.abs < LARGEST
    (value * 100).round.to_i
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
