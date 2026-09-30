require "test_helper"

class BarcodeTest < ActiveSupport::TestCase
  test "calcula el verificador EAN-13 como GS1" do
    assert_equal "4006381333931", Barcode.ean13("400638133393")
    assert Barcode.valido?("7501006559019")
    assert_not Barcode.valido?("7501006559010")
  end

  test "los códigos de identidad se decodifican y llevan prefijo por tipo" do
    codigo = Barcode.identidad("paquete", 90_001, 42)
    assert_equal 13, codigo.length
    assert codigo.start_with?("08")
    assert Barcode.valido?(codigo)
    assert_equal({ tipo: "paquete", plu: 90_001, secuencia: 42 }, Barcode.decodificar_identidad(codigo))
    assert_equal "07", Barcode.identidad("caja", 0, 1)[0, 2]
    assert_equal "06", Barcode.identidad("tarima", 0, 1)[0, 2]
    assert_nil Barcode.decodificar_identidad("7501006559019")
  end

  test "las variantes cubren lo que hacen los lectores" do
    v = Barcode.variantes(" 750100 655901 ")
    assert_includes v, "750100655901"
    assert_includes v, "0750100655901"
    assert_includes v, "7501006559019"
    assert_includes Barcode.variantes("0750100655901"), "750100655901"
    assert_equal [], Barcode.variantes("abc")
  end
end
