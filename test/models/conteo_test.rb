require "test_helper"

class ConteoTest < ActiveSupport::TestCase
  setup do
    @tienda = sucursales(:tienda)
    @super = usuarios(:supervisora)
    @cajera = usuarios(:cajera)
    Inventario.mover!(sucursal: @tienda, producto: productos(:pechuga), tipo: "entrada", cantidad: 5, usuario: @super)
    Inventario.mover!(sucursal: @tienda, producto: productos(:catsup), tipo: "entrada", cantidad: 10, usuario: @super)
  end

  test "abre con la existencia, cada escaneo suma una pieza y lo que va por kilo se teclea" do
    c = Conteo.abrir!(sucursal: @tienda, usuario: @super, responsable: @cajera)
    assert_match(/\AK-\d{5}\z/, c.folio)
    assert_equal({ productos(:pechuga) => BigDecimal("5"), productos(:catsup) => BigDecimal("10") }, c.lineas.to_h { |l| [ l.producto, l.sistema ] })
    2.times { c.escanear!(productos(:catsup)) }
    assert_raises(ArgumentError) { c.escanear!(productos(:pechuga)) }
    c.contar_manual!(productos(:pechuga), "2.5")
    c.contar_manual!(productos(:pechuga), "2")
    assert_equal BigDecimal("2"), c.lineas.find_by(producto: productos(:pechuga)).contado
    assert_equal BigDecimal("2"), c.lineas.find_by(producto: productos(:catsup)).contado
    assert_raises(ArgumentError) { Conteo.abrir!(sucursal: @tienda, usuario: @super, responsable: @cajera) }
  end

  test "un conteo parcial solo toca lo elegido y rechaza lo que está fuera; el cíclico avisa cuando toca" do
    assert_raises(ArgumentError) { Conteo.abrir!(sucursal: @tienda, usuario: @super, responsable: @cajera, productos: []) }
    c = Conteo.abrir!(sucursal: @tienda, usuario: @super, responsable: @cajera, productos: [ productos(:catsup) ])
    assert c.parcial?
    assert_equal [ productos(:catsup) ], c.lineas.map(&:producto)
    assert_raises(ArgumentError) { c.contar_manual!(productos(:pechuga), 1) }
    c.contar_manual!(productos(:catsup), 7)
    c.cerrar!(usuario: @super)
    assert_equal BigDecimal("7"), Existencia.de(@tienda, productos(:catsup))
    assert_equal BigDecimal("5"), Existencia.de(@tienda, productos(:pechuga)), "la pechuga no se tocó"
    assert_equal 1, c.lineas.count

    assert_not Conteo.vencido?(@tienda), "sin frecuencia no vence"
    @tienda.update!(dias_conteo: 7)
    assert_not Conteo.vencido?(@tienda), "acaba de cerrar uno"
    c.update_columns(cerrado_en: 8.days.ago)
    assert Conteo.vencido?(@tienda)
    assert Conteo.vencido?(sucursales(:matriz).tap { |m| m.update!(dias_conteo: 1) }), "nunca ha contado"
  end

  test "al cerrar manda el conteo: ajusta el inventario y carga el faltante" do
    c = Conteo.abrir!(sucursal: @tienda, usuario: @super, responsable: @cajera)
    c.contar_manual!(productos(:pechuga), 2)
    c.contar_manual!(productos(:catsup), 8)
    c.cerrar!(usuario: @super)
    assert_equal "cerrado", c.estado
    assert_equal BigDecimal("2"), Existencia.de(@tienda, productos(:pechuga))
    assert_equal BigDecimal("8"), Existencia.de(@tienda, productos(:catsup))
    # faltan 3 kg de pechuga (3 × 129) y 2 cátsup (2 × 42) = 387 + 84 = 471
    assert_equal 47_100, c.faltante_centavos
    assert_equal 0, c.sobrante_centavos
    cargo = Cargo.last
    assert_equal @cajera, cargo.usuario
    assert_equal 47_100, cargo.monto_centavos
    assert_match "Pechuga", cargo.detalle
    assert_equal 2, Movimiento.where(referencia: c).count
    assert_raises(ArgumentError) { c.cerrar!(usuario: @super) }
    cargo.resolver!("cobrado", usuario: @super)
    assert_equal "cobrado", cargo.estado
    assert_raises(ArgumentError) { cargo.resolver!("perdonado", usuario: @super) }
  end

  test "un sobrante no genera cargo y un conteo exacto no mueve nada" do
    c = Conteo.abrir!(sucursal: @tienda, usuario: @super, responsable: @cajera)
    c.contar_manual!(productos(:pechuga), 5)
    11.times { c.escanear!(productos(:catsup)) }
    c.cerrar!(usuario: @super)
    assert_equal 0, c.faltante_centavos
    assert_equal 4_200, c.sobrante_centavos
    assert_equal 0, Cargo.count
    assert_equal BigDecimal("11"), Existencia.de(@tienda, productos(:catsup))
    assert_equal 1, Movimiento.where(referencia: c).count, "la pechuga cuadró y no se movió"
  end
end
