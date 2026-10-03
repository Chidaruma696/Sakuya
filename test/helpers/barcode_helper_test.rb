require "test_helper"

class BarcodeHelperTest < ActionView::TestCase
  test "encodes 95 modules with the guards in place" do
    bits = ean13_modules("4006381333931")
    assert_equal 95, bits.length
    assert bits.start_with?("101")
    assert bits.end_with?("101")
    assert_equal "01010", bits[45, 5]
    # First digit 4 → parity LGLLGG: the second digit (0) goes in L = 0001101
    assert_equal "0001101", bits[3, 7]
  end

  test "the SVG carries the code as text and rejects invalid codes" do
    svg = ean13_svg("4006381333931")
    assert_match "4006381333931", svg
    assert_match "<rect", svg
    assert_raises(ArgumentError) { ean13_svg("4006381333930") }
  end
end
