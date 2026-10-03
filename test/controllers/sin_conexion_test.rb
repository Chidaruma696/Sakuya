require "test_helper"

class SinConexionTest < ActionDispatch::IntegrationTest
  setup do
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    @tienda = sucursales(:tienda)
    Inventario.mover!(sucursal: @tienda, producto: productos(:catsup), tipo: "entrada", cantidad: 5, usuario: usuarios(:admin))
  end

  def subir(clave, lineas, vendida_en: 10.minutes.ago, pagos: [ { forma: "efectivo", monto_centavos: 100_000 } ])
    post caja_cobrar_path, params: { clave: clave, lineas: lineas.to_json, pagos: pagos.to_json, vendida_en: vendida_en&.iso8601 }, headers: { "Accept" => "application/json" }
  end

  test "el catálogo trae lo que la caja necesita para vender sin conexión" do
    CodigoBarras.create!(producto: productos(:catsup), codigo: "7501234567890")
    get caja_catalogo_path
    catsup = response.parsed_body["productos"].find { |p| p["clave"] == "CATS" }
    assert_equal [ productos(:catsup).id, 4_200 ], catsup.values_at("producto_id", "precio_centavos")
    assert_includes catsup["codigos"], "7501234567890"
    assert catsup.key?("plu")
    get caja_token_path
    assert response.parsed_body["token"].present?
  end

  test "lo vendido sin conexión se registra aunque una regla lo hubiera frenado, y queda reportado; la misma clave no duplica" do
    subir("off-1", [ { producto_id: productos(:catsup).id, cantidad: 1, precio_centavos: 3_000 } ])
    assert_response :ok
    venta = Venta.find_by!(clave: "off-1")
    assert venta.fuera_de_linea
    assert_in_delta 10.minutes.ago, venta.vendida_en, 5
    assert_match "Venta sin conexión que de otra forma se habría frenado", Revision.last.motivo
    assert_equal venta.lineas.first, Revision.last.revisable
    subir("off-1", [ { producto_id: productos(:catsup).id, cantidad: 1, precio_centavos: 3_000 } ])
    assert_equal 1, Venta.where(clave: "off-1").count
  end

  test "sin conexión se vende lo apartado y se reporta; a cuenta no; y la hora tiene que cuadrar" do
    Modulo.guardar!(Modulo::OPCIONALES, comprobar: false)
    lupita = Cliente.create!(nombre: "Fonda Lupita")
    Pedido.create!(cliente: lupita, sucursal: @tienda, usuario: usuarios(:cajera), lineas_attributes: [ { producto_id: productos(:catsup).id, cantidad: 5 } ])
    subir("off-2", [ { producto_id: productos(:catsup).id, cantidad: 1 } ])
    assert_response :ok
    assert_match "apartado para pedidos", Revision.last.motivo
    subir("off-3", [ { producto_id: productos(:catsup).id, cantidad: 1 } ], pagos: [ { forma: "credito", monto_centavos: 4_200 } ])
    assert_match "necesita conexión", response.parsed_body["error"]
    subir("off-4", [ { producto_id: productos(:catsup).id, cantidad: 1 } ], vendida_en: 8.days.ago)
    assert_match "no cuadra", response.parsed_body["error"]
    subir("off-5", [ { producto_id: productos(:catsup).id, cantidad: 1 } ], vendida_en: 1.day.from_now)
    assert_match "no cuadra", response.parsed_body["error"]
  end

  test "con conexión la regla sigue frenando como siempre" do
    subir("on-1", [ { producto_id: productos(:catsup).id, cantidad: 1, precio_centavos: 3_000 } ], vendida_en: nil)
    assert_response :unprocessable_entity
    assert_match "Así no se cobra", response.parsed_body["error"]
  end
end
