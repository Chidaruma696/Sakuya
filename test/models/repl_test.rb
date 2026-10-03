require "test_helper"

class ReplTest < ActiveSupport::TestCase
  setup do
    @tienda = sucursales(:tienda)
    Inventario.mover!(sucursal: @tienda, producto: productos(:catsup), tipo: "entrada", cantidad: 10, usuario: usuarios(:admin))
    Inventario.mover!(sucursal: @tienda, producto: productos(:pechuga), tipo: "entrada", cantidad: 5, usuario: usuarios(:admin))
    cobrar = ->(clave, lineas, usuario) {
      Caja.cobrar!(sucursal: @tienda, usuario: usuario, clave: clave, lineas: lineas, pagos: [ { forma: "efectivo", monto_centavos: 1_000_000 } ])
    }
    cobrar.("a", [ { producto_id: productos(:catsup).id, cantidad: 2 } ], usuarios(:cajera))
    cobrar.("b", [ { producto_id: productos(:pechuga).id, cantidad: "1.5" } ], usuarios(:cajera))
    cobrar.("c", [ { producto_id: productos(:catsup).id, cantidad: 1 } ], usuarios(:supervisora))
  end

  def ev(texto, sucursales: [ @tienda ]) = Repl.evaluar(texto, sucursales: sucursales)

  test "las ventas de hoy como lista de mapas, y las herramientas para sumarlas, contarlas y ordenarlas" do
    ventas = ev("(sales)")
    assert_equal 3, ventas.size
    assert_equal %i[folio date branch cashier customer total change status], ventas.first.keys
    assert_equal BigDecimal("319.50"), ev("(sum-of :total (sales))"), "84 + 193.50 + 42"
    assert_equal({ "Cajera" => 2, "Supervisora" => 1 }, ev("(count-by :cashier (sales))"))
    assert_equal BigDecimal("193.50"), ev("(get (first (sort-by-desc :total (sales))) :total)")
    assert_equal [ "CATS", "CATS" ], ev('(pluck :code (where :code "CATS" (sale-lines)))')
    assert_equal 0, ev("(count (sales (days-ago 30) (days-ago 1)))")
    assert_equal BigDecimal("7"), ev('(get (first (stock "cats")) :quantity)')
  end

  test "solo ve las sucursales que le tocan" do
    assert_equal 0, ev("(count (sales))", sucursales: [ sucursales(:matriz) ])
    assert_equal 3, ev("(count (sales))", sucursales: Sucursal.all)
  end

  test "no escribe aunque lo intente, y explica lo que no entiende" do
    assert_match "solo lee", assert_raises(Lisp::Error) { Repl.solo_lectura { productos(:catsup).update!(nombre: "x") } }.message
    assert_equal "Cátsup 1 kg", productos(:catsup).reload.nombre
    assert_match "no entiendo la fecha", assert_raises(Lisp::Error) { ev('(sales "ayer")') }.message
    assert_match "esperaba un mapa", assert_raises(Lisp::Error) { ev("(sum-of :total (list 1 2))") }.message
    assert_raises(Lisp::Agotado) { ev("(define (f n) (f n)) (f 1)") }
  end
end
