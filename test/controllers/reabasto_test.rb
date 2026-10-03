require "test_helper"

class ReabastoTest < ActionDispatch::IntegrationTest
  setup do
    post entrar_path, params: { usuario: "admin", password: "secreto1" }
    @tienda = sucursales(:tienda)
    Inventario.mover!(sucursal: @tienda, producto: productos(:catsup), tipo: "entrada", cantidad: 2, usuario: usuarios(:admin))
    Inventario.mover!(sucursal: sucursales(:matriz), producto: productos(:catsup), tipo: "entrada", cantidad: 50, usuario: usuarios(:admin))
    Inventario.mover!(sucursal: sucursales(:matriz), producto: productos(:pechuga), tipo: "entrada", cantidad: 50, usuario: usuarios(:admin))
  end

  test "con mínimos y máximos sugiere lo que falta y arma el traspaso" do
    get reabasto_path
    assert_select "#sucursal_#{@tienda.id}", /no le falta nada/
    patch reabasto_minimos_path(sucursal_id: @tienda.id), params: { minimos: {
      productos(:catsup).id => { minimo: "5", maximo: "12" },
      productos(:pechuga).id => { minimo: "1.5", maximo: "" }
    } }
    assert_redirected_to reabasto_path
    assert_equal [ [ productos(:catsup), 10 ], [ productos(:pechuga), BigDecimal("1.5") ] ].sort_by { |p, _| p.nombre },
                 Minimo.sugerido(@tienda).map { |p, c| [ p, c ] }
    get reabasto_path
    assert_select "#sucursal_#{@tienda.id}", /le faltan 2 productos/
    get new_traspaso_path(destino: @tienda.id, sugerido: 1)
    assert_select "select[name='traspaso[sucursal_destino_id]'] option[selected][value=?]", @tienda.id.to_s
    assert_select "input[name$='[cantidad]'][value='10']"
    assert_select "input[name$='[cantidad]'][value='1.5']"
    patch reabasto_minimos_path(sucursal_id: @tienda.id), params: { minimos: { productos(:pechuga).id => { minimo: "" } } }
    assert_equal [ productos(:catsup) ], Minimo.where(sucursal: @tienda).map(&:producto)
    patch reabasto_minimos_path(sucursal_id: @tienda.id), params: { minimos: { productos(:catsup).id => { minimo: "5", maximo: "3" } } }
    assert flash[:alert].present?, "un máximo menor que el mínimo no se guarda"
    assert_equal 12, Minimo.find_by(sucursal: @tienda, producto: productos(:catsup)).maximo
  end
end
