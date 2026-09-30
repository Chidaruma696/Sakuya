require "test_helper"

class EscaneoTest < ActiveSupport::TestCase
  test "resuelve códigos del proveedor, PLU y clave" do
    r = Escaneo.resolver("750100655901")
    assert r.producto?
    assert_equal productos(:catsup), r.producto

    assert_equal productos(:pechuga), Escaneo.resolver("90001").producto
    assert_equal productos(:pechuga), Escaneo.resolver("pech").producto
    assert_nil Escaneo.resolver("nada")
    assert_nil Escaneo.resolver("")
  end
end
