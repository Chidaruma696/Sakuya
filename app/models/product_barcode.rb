class ProductBarcode < ApplicationRecord
  self.table_name = "product_barcodes"

  belongs_to :product

  before_validation { self.code = ProductBarcode.normalize(code) }

  validates :code, presence: true, uniqueness: true, length: { in: 4..32 }

  # Scanners add spaces and sometimes drop the UPC-A leading zero: only digits are kept here.
  def self.normalize(text)
    text.to_s.gsub(/\D/, "")
  end
end
