# Identity EAN-13 codes and scanning helpers. The code identifies a label row; the weight lives
# in the database, never inside the code.
module Barcode
  PREFIXES = { "package" => "08", "till" => "07", "pallet" => "06" }.freeze
  KINDS_BY_PREFIX = PREFIXES.invert.freeze

  def self.digits(text)
    text.to_s.gsub(/\D/, "")
  end

  # EAN/UPC check digit of a string of digits (12 for EAN-13).
  def self.check_digit(body)
    sum = body.each_char.with_index.sum { |c, i| c.to_i * (i.even? ? 1 : 3) }
    (10 - sum % 10) % 10
  end

  def self.ean13(twelve)
    raise ArgumentError, I18n.t("errors.barcode.twelve_digits") unless twelve.match?(/\A\d{12}\z/)
    twelve + check_digit(twelve).to_s
  end

  def self.valid?(code)
    code.to_s.match?(/\A\d{13}\z/) && code[12].to_i == check_digit(code[0, 12])
  end

  # Identity code: kind prefix (2) + PLU (5) + sequence (5) + check digit.
  def self.identity(kind, plu, sequence)
    prefix = PREFIXES.fetch(kind)
    raise ArgumentError, I18n.t("errors.barcode.plu_range") unless (0..99_999).cover?(plu)
    raise ArgumentError, I18n.t("errors.barcode.sequence_range") unless (1..99_999).cover?(sequence)
    ean13(format("%s%05d%05d", prefix, plu, sequence))
  end

  # { kind:, plu:, sequence: } if the code is a valid identity label; nil otherwise.
  def self.decode_identity(code)
    return nil unless valid?(code)
    kind = KINDS_BY_PREFIX[code[0, 2]]
    return nil unless kind
    { kind: kind, plu: code[2, 5].to_i, sequence: code[7, 5].to_i }
  end

  # What the scanner may have meant: with and without check digit, with and without the leading zero (UPC-A).
  def self.variants(text)
    d = digits(text)
    return [] if d.empty?
    v = [ d ]
    v << "0#{d}" if d.length == 12
    v << d[1..] if d.length == 13 && d.start_with?("0")
    v << ean13(d) if d.length == 12
    v << ean13("0#{d}") if d.length == 11
    v << d[0, 12] if d.length == 13
    v.uniq
  end
end
