require "test_helper"

class PromocionTest < ActiveSupport::TestCase
  setup do
    @tienda = sucursales(:tienda)
    @catsup = productos(:catsup) # 42.00
  end

  test "elige la más barata vigente para producto, sucursal y cantidad" do
    Promocion.create!(nombre: "Oferta", producto: @catsup, tipo: "precio", precio_centavos: 3_900)
    Promocion.create!(nombre: "Mayoreo", producto: @catsup, tipo: "por_cantidad", cantidad_minima: 6, precio_centavos: 3_500)
    Promocion.create!(nombre: "10 %", producto: @catsup, tipo: "porcentaje", porcentaje: 10, sucursal: sucursales(:matriz))
    Promocion.create!(nombre: "Vencida", producto: @catsup, tipo: "precio", precio_centavos: 100, hasta: Date.yesterday)
    Promocion.create!(nombre: "Apagada", producto: @catsup, tipo: "precio", precio_centavos: 100, activa: false)
    assert_equal 3_900, Promocion.mejor(@catsup, @tienda, 1, 4_200).first
    assert_equal 3_500, Promocion.mejor(@catsup, @tienda, 6, 4_200).first
    assert_equal 3_780, Promocion.mejor(@catsup, sucursales(:matriz), 1, 4_200).first
    assert_nil Promocion.mejor(productos(:pechuga), @tienda, 1, 12_900)
    assert_nil Promocion.mejor(@catsup, @tienda, 1, 3_000), "una promoción nunca sube el precio"
  end

  test "valida según el tipo y la vigencia" do
    assert_not Promocion.new(nombre: "x", producto: @catsup, tipo: "porcentaje").valid?
    assert_not Promocion.new(nombre: "x", producto: @catsup, tipo: "por_cantidad", precio_centavos: 1).valid?
    assert_not Promocion.new(nombre: "x", producto: @catsup, tipo: "precio", precio_centavos: 1, desde: Date.current, hasta: Date.yesterday).valid?
    assert Promocion.new(nombre: "x", producto: @catsup, tipo: "precio", precio_centavos: 1).valid?
  end
end
