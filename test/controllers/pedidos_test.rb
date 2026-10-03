require "test_helper"

class PedidosTest < ActionDispatch::IntegrationTest
  setup do
    Modulo.guardar!(Modulo::OPCIONALES, comprobar: false)
    post entrar_path, params: { usuario: "supervisora", password: "secreto1" }
    @lupita = Cliente.create!(nombre: "Fonda Lupita")
    Inventario.mover!(sucursal: sucursales(:tienda), producto: productos(:catsup), tipo: "entrada", cantidad: 10, usuario: usuarios(:admin))
  end

  test "se toma el pedido, la caja lo trae armado y al cobrarlo queda entregado" do
    get new_pedido_path
    assert_select "select[name='pedido[cliente_id]'] option", /Fonda Lupita/
    post pedidos_path, params: { pedido: { cliente_id: @lupita.id, lineas_attributes: { "0" => { producto_id: "", cantidad: "" } } } }
    assert_response :unprocessable_entity
    assert_match "no trae renglones", response.body
    post pedidos_path, params: { pedido: { cliente_id: @lupita.id, fecha_entrega: Date.tomorrow, notas: "para la comida",
                                           lineas_attributes: { "0" => { producto_id: productos(:catsup).id, cantidad: "3" } } } }
    pedido = Pedido.last
    assert_redirected_to pedido_path(pedido)
    assert_equal "P-00001", pedido.folio
    get pedidos_path
    assert_select "td", /Cátsup/
    get caja_path(pedido: pedido.id)
    assert_select "#cobrando_pedido", /#{pedido.folio}/
    datos = JSON.parse(css_select("[data-pos-pedido-value]").first["data-pos-pedido-value"])
    assert_equal [ @lupita.id, productos(:catsup).id, 3.0 ], [ datos["cliente_id"], datos["lineas"].first["producto_id"], datos["lineas"].first["cantidad"] ]
    post caja_cobrar_path, params: { clave: "ped", cliente_id: @lupita.id, pedido_id: pedido.id, lineas: [ { producto_id: productos(:catsup).id, cantidad: 3 } ].to_json,
                                     pagos: [ { forma: "efectivo", monto_centavos: 12_600 } ].to_json }, headers: { "Accept" => "application/json" }
    assert_response :ok
    venta = Venta.find_by!(clave: "ped")
    assert_equal [ "entregado", venta, @lupita ], [ pedido.reload.estado, pedido.venta, venta.cliente ]
    get pedido_path(pedido)
    assert_select "a", venta.folio
  end

  test "un pedido se cancela con motivo y ya no se puede cobrar" do
    pedido = Pedido.create!(cliente: @lupita, sucursal: sucursales(:tienda), usuario: usuarios(:supervisora), lineas_attributes: [ { producto_id: productos(:catsup).id, cantidad: 1 } ])
    post cancelar_pedido_path(pedido), params: { motivo: "" }
    assert_match "motivo", flash[:alert]
    post cancelar_pedido_path(pedido), params: { motivo: "ya no lo quiso" }
    assert_equal "cancelado", pedido.reload.estado
    get caja_path(pedido: pedido.id)
    assert_select "#cobrando_pedido", 0
    assert_raises(ArgumentError) { pedido.entregar!(Venta.new) }
  end

  test "el inventario enseña lo apartado y lo disponible, y el pedido dice si aparta" do
    pedido = Pedido.create!(cliente: @lupita, sucursal: sucursales(:tienda), usuario: usuarios(:supervisora), lineas_attributes: [ { producto_id: productos(:catsup).id, cantidad: 4 } ])
    get inventario_path
    assert_select "th", "Apartado"
    assert_select "tr", /CATS.*10.*4.*6/m
    get pedido_path(pedido)
    assert_select ".badge", "aparta existencias"
    get new_pedido_path
    assert_select "input[type=checkbox][name='pedido[apartar]'][checked]"
  end
end
