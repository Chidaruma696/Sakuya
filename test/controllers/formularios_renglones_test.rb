require "test_helper"

# Los formularios con renglones tienen que mandar lineas_attributes, que es lo que leen sus
# controladores. Se lee lo que de verdad pinta cada formulario, no lo que la prueba supone.
class FormulariosRenglonesTest < ActionDispatch::IntegrationTest
  setup do
    Modulo.guardar!(Modulo::OPCIONALES, comprobar: false)
    post entrar_path, params: { usuario: "admin", password: "secreto1" }
  end

  { traspaso: :new_traspaso_path, recepcion: :new_recepcion_path, factura: :new_factura_path, pedido: :new_pedido_path }.each do |modelo, ruta|
    test "el formulario de #{modelo} nombra sus renglones como lineas_attributes" do
      get send(ruta)
      nombres = css_select("[name*='[producto_id]']").map { |e| e["name"] }
      assert nombres.any?, "no hay renglones"
      assert nombres.all? { |n| n.match?(/\A\w+\[lineas_attributes\]\[\d+\]\[producto_id\]\z/) }, nombres.inspect
    end
  end

  test "un traspaso armado con lo que pinta el formulario sí se registra" do
    Inventario.mover!(sucursal: sucursales(:matriz), producto: productos(:catsup), tipo: "entrada", cantidad: 5, usuario: usuarios(:admin))
    get new_traspaso_path
    producto = css_select("select[name*='[producto_id]']").first["name"]
    cantidad = css_select("input[name*='[cantidad]']").first["name"]
    post traspasos_path, params: { "traspaso[sucursal_origen_id]" => sucursales(:matriz).id, "traspaso[sucursal_destino_id]" => sucursales(:tienda).id,
                                   producto => productos(:catsup).id, cantidad => "2", "traspaso[clave]" => "f" }
    assert_redirected_to traspaso_path(Traspaso.last)
    assert_equal BigDecimal("2"), Existencia.de(sucursales(:tienda), productos(:catsup))
  end

  test "una recepción y una factura armadas con lo que pinta el formulario sí se registran" do
    prov = Proveedor.create!(nombre: "Granja", dias_credito: 0)
    get new_recepcion_path
    campos = ->(sel) { css_select(sel).first["name"] }
    post recepciones_path, params: { "recepcion[proveedor_id]" => prov.id, "recepcion[clave]" => "r",
                                     campos.("select[name*='[producto_id]']") => productos(:catsup).id, campos.("input[name*='[cantidad]']") => "4" }
    assert_redirected_to recepcion_path(Recepcion.last)
    assert_equal 1, Recepcion.last.lineas.count
    get new_factura_path
    post facturas_path, params: { "factura[proveedor_id]" => prov.id, "factura[folio]" => "F-1", "factura[fecha]" => Date.current, "factura[recepcion_ids][]" => Recepcion.last.id,
                                  campos.("select[name*='[producto_id]']") => productos(:catsup).id, campos.("input[name*='[cantidad]']") => "4", campos.("input[name*='[precio]']") => "30" }
    assert_redirected_to factura_path(FacturaProveedor.last)
    assert_equal 12_000, FacturaProveedor.last.monto_centavos
  end
end
