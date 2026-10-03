require "test_helper"

class ScanTest < ActiveSupport::TestCase
  test "resolves supplier barcodes, PLU and key" do
    r = Scan.resolve("750100655901")
    assert r.product?
    assert_equal products(:ketchup), r.product

    assert_equal products(:chicken), Scan.resolve("90001").product
    assert_equal products(:chicken), Scan.resolve("chkn").product
    assert_nil Scan.resolve("nothing")
    assert_nil Scan.resolve("")
  end
end
