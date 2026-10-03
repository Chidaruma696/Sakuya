require "test_helper"

class ApartadoTest < ActiveSupport::TestCase
  setup do
    Modulo.guardar!(Modulo::OPCIONALES, comprobar: false)
    @tienda = sucursales(:tienda)
    @catsup = productos(:catsup)
    Inventario.mover!(sucursal: @tienda, producto: @catsup, tipo: "entrada", cantidad: 5, usuario: usuarios(:admin))
    @lupita = Cliente.create!(nombre: "Fonda Lupita")
  end

  def pedido(cantidad, apartar: true)
    Pedido.create!(cliente: @lupita, sucursal: @tienda, usuario: usuarios(:cajera), apartar: apartar, lineas_attributes: [ { producto_id: @catsup.id, cantidad: cantidad } ])
  end

  def vender(cantidad, pedido: nil)
    Caja.cobrar!(sucursal: @tienda, usuario: usuarios(:cajera), clave: SecureRandom.uuid, pedido: pedido, lineas: [ { producto_id: @catsup.id, cantidad: cantidad } ],
                 pagos: [ { forma: "efectivo", monto_centavos: 100_000 } ])
  end

  test "un pedido aparta: lo apartado no se vende ni se traspasa, salvo al cobrar ese pedido" do
    p = pedido(3)
    assert_equal 3, Apartado.de(@tienda, @catsup)
    assert_equal 2, Apartado.disponible(@tienda, @catsup)
    vender(2)
    e = assert_raises(Caja::Error) { vender(1) }
    assert_match "hay 3 pz, pero 3 pz está apartado para pedidos; disponible 0 pz", e.message
    assert_match "apartado", assert_raises(Apartado::Error) {
      Traspaso.registrar!(origen: @tienda, destino: sucursales(:matriz), usuario: usuarios(:admin), lineas: [ { producto_id: @catsup.id, cantidad: 1 } ])
    }.message
    vender(3, pedido: p)
    p.entregar!(Venta.last)
    assert_equal 0, Apartado.de(@tienda, @catsup), "entregado ya no aparta"
  end

  test "un pedido que no alcanza no se guarda; sin apartar sí, y cancelar libera" do
    pedido(4)
    e = assert_raises(ActiveRecord::RecordInvalid) { pedido(2) }
    assert_match "pides 2 pz y hay 1 pz disponible", e.message
    futuro = pedido(20, apartar: false)
    assert_equal 4, Apartado.de(@tienda, @catsup), "sin apartar no cuenta"
    Pedido.first.cancelar!(motivo: "ya no")
    assert_equal 0, Apartado.de(@tienda, @catsup)
    assert futuro.persisted?
  end

  test "las mermas sí pueden tocar lo apartado: registran algo que ya pasó" do
    pedido(5)
    Inventario.mover!(sucursal: @tienda, producto: @catsup, tipo: "merma", cantidad: 1, usuario: usuarios(:admin))
    assert_equal 4, Existencia.de(@tienda, @catsup)
    assert_equal(-1, Apartado.disponible(@tienda, @catsup))
  end

  test "con el módulo de clientes apagado no hay apartados" do
    pedido(3)
    Modulo.guardar!(Modulo::OPCIONALES - %w[clientes], comprobar: false)
    assert_equal({}, Apartado.por_producto(@tienda))
  end

  test "el reabasto cuenta lo disponible, no lo apartado" do
    Minimo.create!(sucursal: @tienda, producto: @catsup, minimo: 3, maximo: 6)
    assert_empty Minimo.sugerido(@tienda), "hay 5"
    pedido(4)
    assert_equal [ [ @catsup, 5 ] ], Minimo.sugerido(@tienda), "disponible 1: faltan 5 para el máximo"
  end
end
