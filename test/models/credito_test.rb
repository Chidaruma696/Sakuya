require "test_helper"

class CreditoTest < ActiveSupport::TestCase
  setup do
    @tienda = sucursales(:tienda)
    @cajera = usuarios(:cajera)
    @catsup = productos(:catsup)
    Inventario.mover!(sucursal: @tienda, producto: @catsup, tipo: "entrada", cantidad: 20, usuario: @cajera)
    @lupita = Cliente.create!(nombre: "Fonda Lupita", limite_credito: "100")
  end

  def a_cuenta(cantidad, cliente: @lupita, usuario: @cajera, efectivo: 0)
    total = 4_200 * cantidad
    Caja.cobrar!(sucursal: @tienda, usuario: usuario, clave: SecureRandom.uuid, cliente: cliente, lineas: [ { producto_id: @catsup.id, cantidad: cantidad } ],
                 pagos: [ { forma: "efectivo", monto_centavos: efectivo }, { forma: "credito", monto_centavos: total - efectivo } ])
  end

  test "de fábrica no se fía: se frena y queda reportado; sin cliente ni se intenta" do
    e = assert_raises(Caja::Frenado) { a_cuenta(1) }
    assert_match "este negocio no vende a cuenta", e.message
    assert_equal [ 0, 0 ], [ Venta.count, MovimientoCredito.count ]
    assert_match "A cuenta de Fonda Lupita por $42.00 frenado", Revision.last.motivo
    assert_match "hay que elegir el cliente", assert_raises(Caja::Error) { a_cuenta(1, cliente: nil) }.message
  end

  test "con la regla del límite se fía hasta el límite, la supervisora fuerza y la cuenta lleva el saldo" do
    Regla.create!(gancho: "credito", codigo: ReglaCredito::EJEMPLO, usuario: usuarios(:admin))
    venta = a_cuenta(2)
    assert_equal @lupita, venta.cliente
    assert_equal 8_400, @lupita.saldo_centavos
    assert_equal [ "cargo", "Venta #{venta.folio}" ], [ MovimientoCredito.last.tipo, MovimientoCredito.last.motivo ]
    assert_match "pasa su límite (debe $84.00, límite $100.00)", assert_raises(Caja::Frenado) { a_cuenta(1) }.message
    a_cuenta(1, efectivo: 2_600)
    assert_equal 10_000, @lupita.saldo_centavos, "lo pagado en efectivo no va a cuenta"
    assert_equal 2_600, Corte.abierto_en(@tienda).efectivo_ventas_centavos
    forzada = a_cuenta(1, usuario: usuarios(:supervisora))
    assert_equal [ forzada, true ], [ Revision.last.revisable, Revision.last.motivo.include?("pasa su límite") ]
  end

  test "devolver lo vendido a cuenta baja la deuda antes que sacar efectivo" do
    Regla.create!(gancho: "credito", codigo: "(allow)", usuario: usuarios(:admin))
    venta = a_cuenta(3, efectivo: 4_200) # 126 de total: 42 en efectivo y 84 a cuenta
    corte = Corte.abierto_en(@tienda)
    gaveta = corte.efectivo_esperado_centavos
    d = Caja.devolver!(venta: venta, lineas: [ { venta_linea_id: venta.lineas.first.id, cantidad: 1 } ], motivo: "rota", usuario: @cajera)
    assert_equal [ 4_200, 4_200 ], [ d.total_centavos, d.a_cuenta_centavos ]
    assert_equal 4_200, @lupita.saldo_centavos
    assert_equal gaveta, corte.efectivo_esperado_centavos, "no salió nada de la gaveta"
    d = Caja.devolver!(venta: venta, lineas: [ { venta_linea_id: venta.lineas.first.id, cantidad: 2 } ], motivo: "rotas", usuario: @cajera)
    assert_equal [ 8_400, 4_200 ], [ d.total_centavos, d.a_cuenta_centavos ]
    assert_equal 0, @lupita.saldo_centavos
    assert_equal gaveta - 4_200, corte.efectivo_esperado_centavos, "lo que se pagó en efectivo sale en efectivo"
  end

  test "la cuenta sabe lo vencido y los días sin abonar" do
    MovimientoCredito.create!(cliente: @lupita, sucursal: @tienda, usuario: @cajera, tipo: "cargo", monto_centavos: 5_000, fecha: 40.days.ago.to_date)
    MovimientoCredito.create!(cliente: @lupita, sucursal: @tienda, usuario: @cajera, tipo: "cargo", monto_centavos: 3_000, fecha: 5.days.ago.to_date)
    MovimientoCredito.create!(cliente: @lupita, sucursal: @tienda, usuario: @cajera, tipo: "abono", monto_centavos: -2_000, fecha: 2.days.ago.to_date)
    cuenta = @lupita.cuenta
    assert_equal 6_000, cuenta.saldo_centavos
    assert_equal 3_000, cuenta.vencido_centavos(30), "el abono mató parte del cargo más viejo"
    assert_equal 2, cuenta.dias_sin_abonar
    d = ReglaCredito.decidir(ReglaCredito.datos(@lupita, monto: 1, total: 1, autorizado: false), codigo: '(if (> (overdue 30) 20) (reject "atrasado") (allow))')
    assert_equal "atrasado", d.motivo
  end
end
