require "test_helper"

class ClientesTest < ActionDispatch::IntegrationTest
  setup do
    Modulo.guardar!(Modulo::OPCIONALES, comprobar: false)
    post entrar_path, params: { usuario: "admin", password: "secreto1" }
  end

  test "alta, búsqueda y edición de clientes, con la pestaña en la cinta" do
    get clientes_path
    assert_select "a[href=?]", new_cliente_path
    assert_match "Todavía no hay clientes", response.body
    post clientes_path, params: { cliente: { nombre: "" } }
    assert_response :unprocessable_entity
    post clientes_path, params: { cliente: { nombre: "Fonda Lupita", telefono: "555 123", limite_credito: "1500" } }
    assert_redirected_to clientes_path
    cliente = Cliente.last
    assert_equal 150_000, cliente.limite_credito_centavos
    get clientes_path(q: "lupi")
    assert_select "td", /Fonda Lupita/
    get clientes_path(q: "nadie")
    assert_select "td", { text: /Fonda Lupita/, count: 0 }
    patch cliente_path(cliente), params: { cliente: { activo: "0" } }
    assert_not cliente.reload.activo
  end

  test "con el módulo apagado no se entra y la cajera sin permiso tampoco" do
    Modulo.guardar!(Modulo::OPCIONALES - %w[clientes], comprobar: false)
    get clientes_path
    assert_response :not_found
    assert_match "Clientes", response.body
    get root_path
    assert_select "nav a[href=?]", clientes_path, 0
    Modulo.guardar!(Modulo::OPCIONALES, comprobar: false)
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get clientes_path
    assert_response :forbidden
  end

  test "estado de cuenta: abonar entra a la gaveta, baja el saldo y la antigüedad se ve" do
    usuarios(:admin).update!(sucursal: sucursales(:tienda))
    lupita = Cliente.create!(nombre: "Fonda Lupita")
    MovimientoCredito.create!(cliente: lupita, sucursal: sucursales(:tienda), usuario: usuarios(:admin), tipo: "cargo", monto_centavos: 30_000, fecha: 45.days.ago.to_date, motivo: "Venta vieja")
    MovimientoCredito.create!(cliente: lupita, sucursal: sucursales(:tienda), usuario: usuarios(:admin), tipo: "cargo", monto_centavos: 10_000, fecha: Date.current, motivo: "Venta nueva")
    get cuenta_cliente_path(lupita)
    assert_select "#saldo", "$400.00"
    assert_select ".card", /31-60 días\s*\$300.00/
    corte = Corte.abierto_en(sucursales(:tienda))
    gaveta = corte.efectivo_esperado_centavos
    post abonar_cliente_path(lupita), params: { monto: "250", forma: "efectivo" }
    assert_redirected_to cuenta_cliente_path(lupita)
    assert_match "ahora debe $150.00", flash[:notice]
    assert_equal gaveta + 25_000, corte.efectivo_esperado_centavos
    post abonar_cliente_path(lupita), params: { monto: "50", forma: "transferencia" }
    assert_equal gaveta + 25_000, corte.efectivo_esperado_centavos, "la transferencia no entra a la gaveta"
    assert_equal 10_000, lupita.saldo_centavos
    get cuenta_cliente_path(lupita)
    assert_select ".card", /31-60 días\s*\$0.00/
    assert_select "td", /Abono AB-/
    post abonar_cliente_path(lupita), params: { monto: "0" }
    assert_match "mayor que cero", flash[:alert]
    get caja_resumen_path(corte)
    assert_match "Abonos", response.body
  end
end
