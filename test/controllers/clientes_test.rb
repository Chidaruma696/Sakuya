require "test_helper"

class ClientesTest < ActionDispatch::IntegrationTest
  setup do
    Modulo.guardar!(Modulo::OPCIONALES, comprobar: false)
    post entrar_path, params: { usuario: "admin", password: "secreto1" }
  end

  test "alta, búsqueda y edición de clientes, con la pestaña en la cinta" do
    get clientes_path
    assert_select "a[href=?]", new_cliente_path
    assert_match "Todavía no hay clientes", response.body
    post clientes_path, params: { cliente: { nombre: "" } }
    assert_response :unprocessable_entity
    post clientes_path, params: { cliente: { nombre: "Fonda Lupita", telefono: "555 123", limite_credito: "1500" } }
    assert_redirected_to clientes_path
    cliente = Cliente.last
    assert_equal 150_000, cliente.limite_credito_centavos
    get clientes_path(q: "lupi")
    assert_select "td", /Fonda Lupita/
    get clientes_path(q: "nadie")
    assert_select "td", { text: /Fonda Lupita/, count: 0 }
    patch cliente_path(cliente), params: { cliente: { activo: "0" } }
    assert_not cliente.reload.activo
  end

  test "con el módulo apagado no se entra y la cajera sin permiso tampoco" do
    Modulo.guardar!(Modulo::OPCIONALES - %w[clientes], comprobar: false)
    get clientes_path
    assert_response :not_found
    assert_match "Clientes", response.body
    get root_path
    assert_select "nav a[href=?]", clientes_path, 0
    Modulo.guardar!(Modulo::OPCIONALES, comprobar: false)
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get clientes_path
    assert_response :forbidden
  end
end
