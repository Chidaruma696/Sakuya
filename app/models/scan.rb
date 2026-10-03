# What was scanned: a product by its barcode, or by a typed PLU or product code.
# Used by the till, receipts and stock counts.
module Scan
  Result = Struct.new(:kind, :product, keyword_init: true) do
    def product? = kind == :product
  end

  def self.resolve(text)
    text = text.to_s.strip
    return nil if text.empty?

    if (code = ProductBarcode.includes(:product).find_by(code: Barcode.variants(text)))
      return Result.new(kind: :product, product: code.product)
    end
    digits = Barcode.digits(text)
    if digits == text && (product = Product.active.find_by(plu: digits.to_i))
      return Result.new(kind: :product, product: product)
    end
    if (product = Product.active.find_by(key: text.upcase))
      return Result.new(kind: :product, product: product)
    end
    nil
  end
end
