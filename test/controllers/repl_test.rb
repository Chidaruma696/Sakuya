require "test_helper"

class ReplControllerTest < ActionDispatch::IntegrationTest
  setup { post entrar_path, params: { usuario: "admin", password: "secreto1" } }

  test "evalúa, pinta una lista de mapas como tabla y recuerda lo último que se preguntó" do
    get repl_path
    assert_select "textarea#texto", "(sales)"
    assert_select "a[href=?]", repl_path
    post repl_evaluar_path, params: { texto: "(products)" }
    assert_response :ok
    assert_select "#resultado th", ":code"
    assert_select "#resultado td", "CATS"
    post repl_evaluar_path, params: { texto: "(+ 1 2.5)" }
    assert_select "#resultado pre", "3.5"
    post repl_evaluar_path, params: { texto: "(count-by :unit (products))" }
    assert_select "#resultado td", "kg"
    post repl_evaluar_path, params: { texto: "(sales" }
    assert_response :unprocessable_entity
    assert_select "#error", /falta cerrar/
    get repl_path
    assert_select "ul a", "(count-by :unit (products))"
    assert_select "ul a", "(products)"
  end

  test "sin reglas.editar no se entra" do
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get repl_path
    assert_response :forbidden
    post repl_evaluar_path, params: { texto: "(products)" }
    assert_response :forbidden
  end
end
