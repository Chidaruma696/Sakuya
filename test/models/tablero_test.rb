require "test_helper"

class TableroTest < ActiveSupport::TestCase
  setup do
    @tienda = sucursales(:tienda)
    Inventario.mover!(sucursal: @tienda, producto: productos(:catsup), tipo: "entrada", cantidad: 10, usuario: usuarios(:admin))
    Caja.cobrar!(sucursal: @tienda, usuario: usuarios(:cajera), clave: "t1", lineas: [ { producto_id: productos(:catsup).id, cantidad: 3 } ],
                 pagos: [ { forma: "efectivo", monto_centavos: 20_000 } ])
    @datos = Tablero::Datos.new(sucursales: [ @tienda ], desde: Date.current, hasta: Date.current)
  end

  def piezas(codigo) = Tablero.evaluar(codigo, @datos)

  test "el de fábrica trae las ocho cifras de siempre y las tres listas" do
    p = piezas(Tablero::DE_FABRICA)
    assert_equal 8, p.count { |x| x.tipo == :tile }
    assert_equal %i[top-products closed-cash-counts stock-counts], p.select { |x| x.tipo == :panel }.map(&:panel)
    ventas = p.first
    assert_equal "Sales", I18n.with_locale(:en) { piezas("(dashboard (tile :sales))").first.titulo }
    assert_equal BigDecimal("126"), ventas.valor
    assert_equal :money, ventas.formato
  end

  test "cifras propias, condicionales y por producto" do
    p = piezas(<<~LISP)
      (define margen (- (sales) (returns)))
      (dashboard
        (tile "Margen" margen :money)
        (tile "Cátsup vendida" (sold "cats"))
        (when (> (returns) 0) (tile :returns))
        (map (fn (d) (tile (str "Día " d) d)) '(1 2))
        (panel :top-products 3))
    LISP
    assert_equal [ "Margen", "Cátsup vendida", "Día 1", "Día 2", nil ], p.map(&:titulo)
    assert_equal BigDecimal("126"), p[0].valor
    assert_equal BigDecimal("3"), p[1].valor
    assert_equal 3, p.last.limite
  end

  test "lo que no cuadra se dice en palabras" do
    assert_match "(dashboard", assert_raises(Lisp::Error) { piezas("(tile :sales)") }.message
    assert_match "no hay cifra :ventas", assert_raises(Lisp::Error) { piezas("(dashboard (tile :ventas))") }.message
    assert_match "no hay lista :mermas", assert_raises(Lisp::Error) { piezas("(dashboard (panel :mermas))") }.message
    assert_match "no hay producto con clave NADA", assert_raises(Lisp::Error) { piezas(%((dashboard (tile "x" (sold "nada"))))) }.message
    assert_match "el formato", assert_raises(Lisp::Error) { piezas(%((dashboard (tile "x" 1 :pesos)))) }.message
    assert_raises(Lisp::Error) { piezas("(dashboard 42)") }
  end

  test "si el programa guardado truena, sale el de fábrica con el porqué" do
    p, error = Tablero.armar(@datos, codigo: "(dashboard (tile :nada))")
    assert_match "no hay cifra", error
    assert_equal 8, p.count { |x| x.tipo == :tile }
    p, error = Tablero.armar(@datos, codigo: "(dashboard (tile :tickets))")
    assert_nil error
    assert_equal [ 1 ], p.map(&:valor)
  end

  test "las reglas no se editan ni se borran; la vigente es la última" do
    r = Regla.create!(gancho: "tablero", codigo: "(dashboard)", usuario: usuarios(:admin))
    Regla.create!(gancho: "tablero", codigo: "(dashboard (tile :sales))", usuario: usuarios(:admin))
    assert_equal "(dashboard (tile :sales))", Regla.vigente("tablero").codigo
    assert_raises(ActiveRecord::ReadOnlyRecord) { r.update!(codigo: "x") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { r.destroy! }
    assert_not Regla.new(gancho: "otro", codigo: "1", usuario: usuarios(:admin)).valid?
  end
end
