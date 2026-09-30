require "test_helper"

# Compras: recepción que entra al inventario, factura que crea la deuda (el precio
# solo vive ahí), pago que sale de la gaveta y abona en la misma transacción, anulación que
# compensa, cancelaciones con sus candados y el comparativo facturado contra recibido.
class ComprasTest < ActiveSupport::TestCase
  setup do
    @matriz = sucursales(:matriz)
    @admin = usuarios(:admin)
    @pechuga = productos(:pechuga)
    @catsup = productos(:catsup)
    @prov = Proveedor.create!(nombre: "Avícola del Valle", dias_credito: 15)
  end

  def recibir(lineas = [ { producto_id: @pechuga.id, cantidad: "20", cajas: 2 } ], **extra)
    Compras.recibir!(sucursal: @matriz, proveedor: @prov, usuario: @admin, lineas: lineas, **extra)
  end

  test "recibir entra al inventario, lleva folio RC por sucursal y es idempotente por clave" do
    r = recibir(remision: "R-77", clave: "abc")
    assert_match(/\ARC-/, r.folio)
    assert_equal 20, Existencia.de(@matriz, @pechuga)
    assert_equal r, recibir(clave: "abc"), "la misma clave devuelve la misma recepción"
    assert_equal 20, Existencia.de(@matriz, @pechuga)
    assert_raises(Compras::Error) { recibir([]) }
  end

  test "cancelar la recepción saca la mercancía y suelta la factura" do
    f = Compras.facturar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, folio: "A-1", fecha: Date.current, monto_centavos: 100_00)
    r = recibir(factura: f)
    Compras.cancelar_recepcion!(r, motivo: "se capturó doble", usuario: @admin)
    assert r.reload.cancelada?
    assert_nil r.factura
    assert_equal 0, Existencia.de(@matriz, @pechuga)
    assert_raises(Compras::Error) { Compras.cancelar_recepcion!(r, motivo: "otra vez", usuario: @admin) }
  end

  test "la factura crea la deuda: con renglones el monto se deriva, vence por los días de crédito y el folio no se repite" do
    f = Compras.facturar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, folio: "F-100", fecha: Date.new(2026, 9, 1),
                          lineas: [ { producto_id: @pechuga.id, cantidad: "10", precio: "95.50" }, { producto_id: @catsup.id, cantidad: "3", precio: "30" } ])
    assert_equal 955_00 + 90_00, f.monto_centavos
    assert_equal Date.new(2026, 9, 16), f.vence
    assert_equal f.monto_centavos, @prov.saldo_centavos
    assert_equal 0, Existencia.de(@matriz, @pechuga), "facturar no toca el inventario"
    assert_raises(Compras::Error) { Compras.facturar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, folio: "F-100", fecha: Date.current, monto_centavos: 1) }
    assert_raises(Compras::Error) { Compras.facturar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, folio: "F-101", fecha: Date.current, monto_centavos: 0) }
  end

  test "el pago en efectivo sale de la gaveta como retiro y abona; sin caja abierta no hay pago en efectivo" do
    f = Compras.facturar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, folio: "F-1", fecha: Date.current, monto_centavos: 500_00)
    assert_raises(Compras::Error) { Compras.pagar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, monto_centavos: 100_00, factura: f) }
    corte = Corte.abrir!(sucursal: @matriz, usuario: @admin, fondo_centavos: 1_000_00)
    pago = Compras.pagar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, monto_centavos: 300_00, factura: f)
    assert_equal 300_00, pago.retiro.monto_centavos
    assert_equal 700_00, corte.reload.efectivo_esperado_centavos
    assert_equal 200_00, f.reload.resta_centavos
    assert_equal 200_00, @prov.saldo_centavos
    assert_raises(Compras::Error, "no pasa de lo que resta") { Compras.pagar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, monto_centavos: 200_01, factura: f) }
    assert_raises(Compras::Error, "más de lo que se debe sin factura") { Compras.pagar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, monto_centavos: 200_01) }
    transferencia = Compras.pagar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, monto_centavos: 200_00, forma: "transferencia", factura: f)
    assert_nil transferencia.retiro
    assert_equal 700_00, corte.reload.efectivo_esperado_centavos, "la transferencia no toca la caja"
    assert f.reload.pagada?
    assert_equal 0, @prov.saldo_centavos
  end

  test "anular un pago compensa el abono y regresa el efectivo solo con el corte abierto" do
    f = Compras.facturar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, folio: "F-2", fecha: Date.current, monto_centavos: 500_00)
    corte = Corte.abrir!(sucursal: @matriz, usuario: @admin, fondo_centavos: 1_000_00)
    pago = Compras.pagar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, monto_centavos: 300_00, factura: f)
    Compras.anular_pago!(pago, motivo: "se pagó dos veces", usuario: @admin)
    assert_equal "anulado", pago.reload.estado
    assert_equal 1_000_00, corte.reload.efectivo_esperado_centavos
    assert_equal 500_00, @prov.saldo_centavos
    assert_equal 500_00, f.reload.resta_centavos
    assert_equal %w[cargo abono ajuste], @prov.movimientos.order(:id).pluck(:tipo)

    otro = Compras.pagar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, monto_centavos: 100_00, factura: f)
    corte.cerrar!(contado_centavos: corte.reload.efectivo_esperado_centavos, usuario: @admin)
    assert_raises(Compras::Error) { Compras.anular_pago!(otro, motivo: "tarde", usuario: @admin) }
    assert otro.reload.vigente?
  end

  test "cancelar la factura revierte la deuda, suelta recepciones y se niega con pagos vigentes" do
    f = Compras.facturar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, folio: "F-3", fecha: Date.current, monto_centavos: 400_00)
    r = recibir(factura: f)
    Compras.facturar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, folio: "F-4", fecha: Date.current, monto_centavos: 50_00)
    corte = Corte.abrir!(sucursal: @matriz, usuario: @admin, fondo_centavos: 1_000_00)
    pago = Compras.pagar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, monto_centavos: 100_00, factura: f)
    assert_raises(Compras::Error) { Compras.cancelar_factura!(f, motivo: "mal capturada", usuario: @admin) }
    Compras.anular_pago!(pago, motivo: "para cancelar", usuario: @admin)
    Compras.cancelar_factura!(f, motivo: "mal capturada", usuario: @admin)
    assert f.reload.cancelada?
    assert_nil r.reload.factura
    assert r.registrada?, "la mercancía se queda"
    assert_equal 50_00, @prov.saldo_centavos
    assert_equal 1_000_00, corte.reload.efectivo_esperado_centavos
  end

  test "el comparativo dice qué falta y qué sobra entre lo facturado y lo recibido" do
    f = Compras.facturar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, folio: "F-5", fecha: Date.current,
                          lineas: [ { producto_id: @pechuga.id, cantidad: "20", precio: "90" }, { producto_id: @catsup.id, cantidad: "5", precio: "30" } ])
    recibir([ { producto_id: @pechuga.id, cantidad: "18" } ], factura: f)
    recibir([ { producto_id: @pechuga.id, cantidad: "2" } ], factura: f)
    otro = Producto.create!(clave: "HIELO", nombre: "Hielo", linea: "Insumos", unidad: "pieza", precio_centavos: 100)
    recibir([ { producto_id: otro.id, cantidad: "1" } ], factura: f)
    estados = Compras.comparativo(f).to_h { |c| [ c.producto.clave, c.estado ] }
    assert_equal({ "CATS" => "sin_recibir", "HIELO" => "sin_facturar", "PECH" => "cuadra" }, estados)
  end

  test "los libros no se editan ni se borran" do
    Compras.facturar!(proveedor: @prov, sucursal: @matriz, usuario: @admin, folio: "F-6", fecha: Date.current, monto_centavos: 10_00)
    assert_raises(ActiveRecord::ReadOnlyRecord) { @prov.movimientos.first.destroy! }
    assert_raises(ActiveRecord::RecordNotDestroyed) { @prov.destroy! }
  end
end
