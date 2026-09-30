require "test_helper"

class BarcodeHelperTest < ActionView::TestCase
  test "codifica 95 módulos con las guardas en su sitio" do
    bits = ean13_modulos("4006381333931")
    assert_equal 95, bits.length
    assert bits.start_with?("101")
    assert bits.end_with?("101")
    assert_equal "01010", bits[45, 5]
    # Primer dígito 4 → paridad LGLLGG: el segundo dígito (0) va en L = 0001101
    assert_equal "0001101", bits[3, 7]
  end

  test "el SVG lleva el código como texto y rechaza códigos inválidos" do
    svg = ean13_svg("4006381333931")
    assert_match "4006381333931", svg
    assert_match "<rect", svg
    assert_raises(ArgumentError) { ean13_svg("4006381333930") }
  end
end
