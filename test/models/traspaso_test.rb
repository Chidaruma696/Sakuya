require "test_helper"

# Traspasos y almacenes: sale y entra en la misma transacción; de un almacén solo a la matriz;
# cancelar regresa la mercancía; en un almacén no hay caja.
class TraspasoTest < ActiveSupport::TestCase
  setup do
    @matriz = sucursales(:matriz)
    @tienda = sucursales(:tienda)
    @admin = usuarios(:admin)
    @pechuga = productos(:pechuga)
    @frio = Sucursal.create!(codigo: "FRI", nombre: "Frigorífico", tipo: "almacen", limite_efectivo_centavos: 1)
    Inventario.mover!(sucursal: @matriz, producto: @pechuga, tipo: "entrada", cantidad: 5000, usuario: @admin)
  end

  def traspasar(origen, destino, cantidad, **extra)
    Traspaso.registrar!(origen: origen, destino: destino, usuario: @admin, lineas: [ { producto_id: @pechuga.id, cantidad: cantidad, cajas: 10 } ], **extra)
  end

  test "sale y entra en la misma transacción, con folio TG e idempotente por clave" do
    t = traspasar(@matriz, @frio, 3000, clave: "c1")
    assert_match(/\ATG-/, t.folio)
    assert_equal 2000, Existencia.de(@matriz, @pechuga)
    assert_equal 3000, Existencia.de(@frio, @pechuga)
    assert_equal t, traspasar(@matriz, @frio, 3000, clave: "c1")
    assert_equal 2000, Existencia.de(@matriz, @pechuga)
    assert_equal %w[salida entrada], t.movimientos.order(:id).pluck(:tipo)
    assert_raises(Inventario::SinExistencia) { traspasar(@matriz, @frio, 9999) }
  end

  test "de un almacén externo la mercancía solo va a la matriz" do
    traspasar(@matriz, @frio, 3000)
    assert_raises(Traspaso::Error) { traspasar(@frio, @tienda, 100) }
    traspasar(@frio, @matriz, 1000)
    assert_equal 3000, Existencia.de(@matriz, @pechuga)
  end

  test "cancelar regresa la mercancía al origen" do
    t = traspasar(@matriz, @frio, 3000)
    t.cancelar!(motivo: "camión equivocado", usuario: @admin)
    assert t.cancelado?
    assert_equal 5000, Existencia.de(@matriz, @pechuga)
    assert_equal 0, Existencia.de(@frio, @pechuga)
    assert_raises(Traspaso::Error) { t.cancelar!(motivo: "otra vez", usuario: @admin) }
  end

  test "en un almacén no hay caja" do
    assert_raises(ArgumentError) { Corte.abrir!(sucursal: @frio, usuario: @admin, fondo_centavos: 0) }
  end
end
