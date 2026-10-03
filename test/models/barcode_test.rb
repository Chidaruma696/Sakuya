require "test_helper"

class BarcodeTest < ActiveSupport::TestCase
  test "computes the EAN-13 check digit the GS1 way" do
    assert_equal "4006381333931", Barcode.ean13("400638133393")
    assert Barcode.valid?("7501006559019")
    assert_not Barcode.valid?("7501006559010")
  end

  test "identity codes decode back and carry a prefix per kind" do
    code = Barcode.identity("package", 90_001, 42)
    assert_equal 13, code.length
    assert code.start_with?("08")
    assert Barcode.valid?(code)
    assert_equal({ kind: "package", plu: 90_001, sequence: 42 }, Barcode.decode_identity(code))
    assert_equal "07", Barcode.identity("till", 0, 1)[0, 2]
    assert_equal "06", Barcode.identity("pallet", 0, 1)[0, 2]
    assert_nil Barcode.decode_identity("7501006559019")
  end

  test "the variants cover what scanners do" do
    v = Barcode.variants(" 750100 655901 ")
    assert_includes v, "750100655901"
    assert_includes v, "0750100655901"
    assert_includes v, "7501006559019"
    assert_includes Barcode.variants("0750100655901"), "750100655901"
    assert_equal [], Barcode.variants("abc")
  end
end
