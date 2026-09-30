require "test_helper"

class CajaTest < ActiveSupport::TestCase
  setup do
    @tienda = sucursales(:tienda)
    @cajera = usuarios(:cajera)
    @pechuga = productos(:pechuga)
    @catsup = productos(:catsup)
    Inventario.mover!(sucursal: @tienda, producto: @pechuga, tipo: "entrada", cantidad: 10, usuario: @cajera)
    Inventario.mover!(sucursal: @tienda, producto: @catsup, tipo: "entrada", cantidad: 5, usuario: @cajera)
    @pesada = { producto_id: @pechuga.id, cantidad: "1.250" }
  end

  def cobrar(lineas, pagos = nil, **extra)
    Caja.cobrar!(sucursal: @tienda, usuario: @cajera, lineas: lineas, clave: SecureRandom.uuid,
                 pagos: pagos || [ { forma: "efectivo", monto_centavos: 1_000_000 } ], **extra)
  end

  test "cobra un producto por kilo y otro por pieza, descuenta inventario y da cambio" do
    venta = Caja.cobrar!(sucursal: @tienda, usuario: @cajera, clave: "t1",
                         lineas: [ @pesada, { producto_id: @catsup.id, cantidad: 2 } ],
                         pagos: [ { forma: "efectivo", monto_centavos: 30_000 } ])
    # 1.250 × 129.00 = 161.25 ; 2 × 42.00 = 84.00 → 245.25
    assert_equal 24_525, venta.total_centavos
    assert_equal 5_475, venta.cambio_centavos
    assert_match(/\AB-\d{5}\z/, venta.folio)
    assert Barcode.valido?(venta.codigo)
    assert venta.codigo.start_with?("09")
    assert_equal BigDecimal("8.75"), Existencia.de(@tienda, @pechuga)
    assert_equal BigDecimal("3"), Existencia.de(@tienda, @catsup)
    assert_equal 2, Movimiento.where(referencia: venta).count
    # la misma clave no cobra dos veces
    assert_equal venta, Caja.cobrar!(sucursal: @tienda, usuario: @cajera, clave: "t1", lineas: [ { producto_id: @catsup.id, cantidad: 1 } ], pagos: [])
  end

  test "un producto sin precio en la sucursal se recibe pero no se vende" do
    @catsup.update!(precio_centavos: 0)
    e = assert_raises(Caja::Error) { cobrar([ { producto_id: @catsup.id, cantidad: 1 } ]) }
    assert_match "sin precio", e.message
    @catsup.fijar_precio!(@tienda, "40")
    assert_equal 4_000, cobrar([ { producto_id: @catsup.id, cantidad: 1 } ]).total_centavos
  end

  test "pagos mixtos: lo que no es efectivo no puede pasarse del total y el cambio sale del efectivo" do
    venta = Caja.cobrar!(sucursal: @tienda, usuario: @cajera, clave: "t2", lineas: [ { producto_id: @catsup.id, cantidad: 3 } ],
                         pagos: [ { forma: "transferencia", monto_centavos: 10_000 }, { forma: "efectivo", monto_centavos: 5_000 } ])
    assert_equal 12_600, venta.total_centavos
    assert_equal 2_400, venta.cambio_centavos
    assert_raises(Caja::Error) do
      Caja.cobrar!(sucursal: @tienda, usuario: @cajera, clave: "t3", lineas: [ { producto_id: @catsup.id, cantidad: 1 } ],
                   pagos: [ { forma: "transferencia", monto_centavos: 10_000 } ])
    end
    assert_raises(Caja::Error) do
      Caja.cobrar!(sucursal: @tienda, usuario: @cajera, clave: "t4", lineas: [ { producto_id: @catsup.id, cantidad: 1 } ],
                   pagos: [ { forma: "efectivo", monto_centavos: 100 } ])
    end
  end

  test "no vende sin existencia, sin caja abierta, ni piezas fraccionadas" do
    e = assert_raises(Caja::Error) { cobrar([ { producto_id: @catsup.id, cantidad: 6 } ]) }
    assert_match "No se vende lo que no hay", e.message
    assert_raises(Caja::Error) { cobrar([ { producto_id: @catsup.id, cantidad: "1.5" } ]) }
    cortes(:tienda_abierto).update!(estado: "cerrado")
    e = assert_raises(Caja::Error) { cobrar([ { producto_id: @catsup.id, cantidad: 1 } ]) }
    assert_match "no hay caja abierta", e.message
    assert_equal 0, Venta.count
  end

  test "bajar el precio queda a nombre de quien tiene el permiso (o sin nadie, por revisar) y nunca baja de la mitad" do
    linea = { producto_id: @catsup.id, cantidad: 1, precio_centavos: 3_000 }
    sola = cobrar([ linea ], [ { forma: "efectivo", monto_centavos: 3_000 } ])
    assert_nil sola.lineas.first.autorizado_por, "sin permiso se cobra igual; el controlador lo deja por revisar"
    assert_equal 3_000, sola.lineas.first.precio_centavos
    venta = cobrar([ linea ], [ { forma: "efectivo", monto_centavos: 3_000 } ], autorizador: usuarios(:supervisora))
    assert_equal usuarios(:supervisora), venta.lineas.first.autorizado_por
    assert_equal 4_200, venta.lineas.first.catalogo_centavos
    assert_raises(Caja::Error) { cobrar([ { producto_id: @catsup.id, cantidad: 1, precio_centavos: 2_000 } ], [ { forma: "efectivo", monto_centavos: 2_000 } ], autorizador: usuarios(:supervisora)) }
  end

  test "el corte cuadra: fondo + efectivo de ventas − devoluciones − retiros, y bloquea al pasar el límite" do
    corte = cortes(:tienda_abierto)
    venta = Caja.cobrar!(sucursal: @tienda, usuario: @cajera, clave: "t5", lineas: [ @pesada ],
                         pagos: [ { forma: "efectivo", monto_centavos: 20_000 } ])
    assert_equal 50_000 + 16_125, corte.efectivo_esperado_centavos
    corte.retirar!(monto_centavos: 10_000, motivo: "caja fuerte", usuario: @cajera, autorizado_por: usuarios(:supervisora))
    assert_equal 56_125, corte.efectivo_esperado_centavos
    assert_raises(ArgumentError) { corte.retirar!(monto_centavos: 100_000, motivo: "x", usuario: @cajera, autorizado_por: usuarios(:supervisora)) }

    dev = Caja.devolver!(venta: venta, lineas: [ { venta_linea_id: venta.lineas.first.id, cantidad: "1.250" } ], motivo: "no le gustó", usuario: @cajera)
    assert_equal 16_125, dev.total_centavos
    assert_equal "devuelta", venta.reload.estado
    assert_equal BigDecimal("10"), Existencia.de(@tienda, @pechuga)
    assert_equal 40_000, corte.efectivo_esperado_centavos
    assert_raises(Caja::Error) { Caja.devolver!(venta: venta, lineas: [ { venta_linea_id: venta.lineas.first.id, cantidad: 1 } ], motivo: "otra vez", usuario: @cajera) }

    @tienda.update!(limite_efectivo_centavos: 45_000)
    Caja.cobrar!(sucursal: @tienda, usuario: @cajera, clave: "t6", lineas: [ { producto_id: @catsup.id, cantidad: 2 } ], pagos: [ { forma: "efectivo", monto_centavos: 8_400 } ])
    e = assert_raises(Caja::Error) { Caja.cobrar!(sucursal: @tienda, usuario: @cajera, clave: "t7", lineas: [ { producto_id: @catsup.id, cantidad: 1 } ], pagos: [ { forma: "efectivo", monto_centavos: 4_200 } ]) }
    assert_match "retiro", e.message

    corte.cerrar!(contado_centavos: 48_000, usuario: @cajera)
    assert_equal 48_400, corte.esperado_centavos
    assert_equal(-400, corte.diferencia_centavos)
    nuevo = Corte.abrir!(sucursal: @tienda, usuario: @cajera, fondo_centavos: 30_000)
    assert_raises(ArgumentError) { Corte.abrir!(sucursal: @tienda, usuario: @cajera, fondo_centavos: 1) }
    assert_equal 30_000, nuevo.efectivo_esperado_centavos
  end

  test "devolución parcial deja la venta cobrada y respeta lo pendiente" do
    venta = Caja.cobrar!(sucursal: @tienda, usuario: @cajera, clave: "t8", lineas: [ { producto_id: @catsup.id, cantidad: 3 } ], pagos: [ { forma: "efectivo", monto_centavos: 12_600 } ])
    linea = venta.lineas.first
    Caja.devolver!(venta: venta, lineas: [ { venta_linea_id: linea.id, cantidad: 1 } ], motivo: "abollada", usuario: @cajera)
    assert venta.reload.cobrada?
    assert_equal BigDecimal("2"), linea.cantidad_pendiente
    assert_raises(Caja::Error) { Caja.devolver!(venta: venta, lineas: [ { venta_linea_id: linea.id, cantidad: 3 } ], motivo: "x", usuario: @cajera) }
    assert_equal Venta.buscar(venta.codigo), venta
    assert_equal Venta.buscar(" #{venta.folio.downcase} "), venta
  end

  test "el precio de la sucursal manda sobre el general, y el piso se mide contra él" do
    @catsup.fijar_precio!(@tienda, "50.00")
    venta = cobrar([ { producto_id: @catsup.id, cantidad: 1 } ])
    assert_equal 5_000, venta.lineas.first.catalogo_centavos
    assert_equal 4_200, @catsup.precio_centavos_en(sucursales(:matriz))
    @catsup.fijar_precio!(@tienda, "")
    assert_equal 4_200, @catsup.reload.precio_centavos_en(@tienda)
  end

  test "la caja aplica la promoción sola, la marca en la línea y la rebaja se mide contra ella" do
    Inventario.mover!(sucursal: @tienda, producto: @catsup, tipo: "entrada", cantidad: 20, usuario: @cajera)
    promo = Promocion.create!(nombre: "Mayoreo", producto: @catsup, tipo: "por_cantidad", cantidad_minima: 3, precio_centavos: 3_500)
    venta = cobrar([ { producto_id: @catsup.id, cantidad: 3 } ])
    linea = venta.lineas.first
    assert_equal 3_500, linea.precio_centavos
    assert_equal 4_200, linea.catalogo_centavos
    assert_equal promo, linea.promocion
    assert_equal 10_500, venta.total_centavos
    sin = cobrar([ { producto_id: @catsup.id, cantidad: 2 } ])
    assert_nil sin.lineas.first.promocion
    assert_equal 4_200, sin.lineas.first.precio_centavos
    assert_nil cobrar([ { producto_id: @catsup.id, cantidad: 3, precio_centavos: 3_400 } ]).lineas.first.autorizado_por
    con = cobrar([ { producto_id: @catsup.id, cantidad: 3, precio_centavos: 3_400 } ], nil, autorizador: usuarios(:supervisora))
    assert_nil con.lineas.first.promocion
    assert_equal usuarios(:supervisora), con.lineas.first.autorizado_por
  end

  test "dinero: formato y redondeo" do
    assert_equal "$1,234.50", Dinero.pesos(123_450)
    assert_equal "−$0.05", Dinero.pesos(-5)
    assert_equal 12_900, Dinero.centavos("129.00")
    assert_equal 16_125, Dinero.importe("1.250", 12_900)
    assert_equal 4_302, Dinero.importe("0.3335", 12_900)
  end
end
