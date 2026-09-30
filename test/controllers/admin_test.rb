require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  setup { post entrar_path, params: { usuario: "admin", password: "secreto1" } }

  test "productos: crear, editar, códigos de barras" do
    get admin_productos_path
    assert_select "td", /Pechuga/
    post admin_productos_path, params: { producto: { clave: "ala", nombre: "Ala de pollo", linea: "Pollo", unidad: "kg", precio: "75.50", activo: "1" } }
    assert_redirected_to edit_admin_producto_path(Producto.find_by!(clave: "ALA"))
    p = Producto.find_by!(clave: "ALA")
    assert_equal 7_550, p.precio_centavos
    assert_operator p.plu, :>=, 90_000
    post admin_producto_codigos_path(p), params: { codigo: "750 1234 567890" }
    assert_equal "7501234567890", p.codigos_barras.first.codigo
    delete admin_producto_codigo_path(p, p.codigos_barras.first)
    assert_equal 0, p.codigos_barras.count
    patch admin_producto_path(p), params: { producto: { clave: "ALA", nombre: "Ala", unidad: "kg", precio: "0", activo: "0" } }
    assert_equal false, p.reload.activo
    post admin_productos_path, params: { producto: { clave: "", nombre: "", unidad: "kg" } }
    assert_response :unprocessable_entity
    patch admin_producto_path(p), params: { producto: { clave: "ALA", nombre: "Ala", unidad: "kg", precio: "75.50", activo: "1" }, precios: { sucursales(:tienda).id => "80", sucursales(:matriz).id => "" } }
    assert_equal 8_000, p.reload.precio_centavos_en(sucursales(:tienda))
    assert_equal 7_550, p.precio_centavos_en(sucursales(:matriz))
    get edit_admin_producto_path(p)
    assert_select "input[name='precios[#{sucursales(:tienda).id}]'][value='80.0']"
  end

  test "usuarios y roles: crear, cambiar rol, permisos con comodín" do
    post admin_roles_path, params: { rol: { nombre: "bodega", permisos: [ "", "compras.*", "conteos.hacer" ] } }
    rol = Rol.find_by!(nombre: "bodega")
    assert rol.permite?("compras.facturar")
    assert_not rol.permite?("caja.vender")
    post admin_usuarios_path, params: { usuario: { nombre: "Beto", usuario: "Beto", rol_id: rol.id, sucursal_id: sucursales(:matriz).id, password: "clave1234", activo: "1" } }
    u = Usuario.find_by!(usuario: "beto")
    assert u.authenticate("clave1234")
    patch admin_usuario_path(u), params: { usuario: { nombre: "Beto", usuario: "beto", rol_id: roles(:cajero).id, sucursal_id: sucursales(:tienda).id, password: "", activo: "1" } }
    assert u.reload.authenticate("clave1234"), "la contraseña no cambia si se deja vacía"
    assert_equal roles(:cajero), u.rol
    patch admin_rol_path(rol), params: { rol: { nombre: "bodega", permisos: [ "*" ] } }
    assert rol.reload.permite?("admin.usuarios")
    get admin_roles_path
    assert_select "td", /bodega/
  end

  test "promociones: crear, listar y borrar" do
    post admin_promociones_path, params: { promocion: { nombre: "Martes", producto_id: productos(:catsup).id, sucursal_id: "", tipo: "precio", precio: "39.90", cantidad_minima: "", activa: "1" } }
    promo = Promocion.last
    assert_redirected_to admin_promociones_path
    assert_equal 3_990, promo.precio_centavos
    assert_nil promo.sucursal_id
    get admin_promociones_path
    assert_select "td", /Martes/
    get caja_escanear_path(codigo: "CATS"), headers: { "Accept" => "application/json" }
    assert_equal "Martes", response.parsed_body["promociones"].first["nombre"]
    delete admin_promocion_path(promo)
    assert_equal 0, Promocion.count
  end

  test "sucursales con límite en pesos y sin permiso 403" do
    post admin_sucursales_path, params: { sucursal: { codigo: "t03", nombre: "Tienda 3", tipo: "tienda", limite_efectivo: "5000", activa: "1" } }
    s = Sucursal.find_by!(codigo: "T03")
    assert_equal 500_000, s.limite_efectivo_centavos
    delete salir_path
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get admin_productos_path
    assert_response :forbidden
  end
end
