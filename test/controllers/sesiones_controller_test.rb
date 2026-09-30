require "test_helper"

class AcercaDeTest < ActionDispatch::IntegrationTest
  test "el logo de la cinta abre el Acerca de con versión, build y sesión" do
    post entrar_path, params: { usuario: "admin", password: "secreto1" }
    get root_path
    assert_select "button[title='Acerca de Sakuya'] img[alt=Sakuya]"
    # En pantalla angosta la cinta vive en una barra lateral con las mismas pestañas y botones
    assert_select "aside[data-lateral-target=panel]" do
      assert_select "a", /Recibir/
      assert_select "a", /Conteo/
    end
    assert_select "dialog[data-dialogo-target=dialogo]" do
      assert_select "dd", /#{Regexp.escape(Sakuya::VERSION)}/
      assert_select "dd", /Rails #{Regexp.escape(Rails.version)}/
      assert_select "dd", /Administrador/
      assert_select "a[href='https://github.com/Chidaruma696/Sakuya']"
    end
    get entrar_path
    assert_response :redirect, "con sesión no vuelve al login"
  end
end

class SesionesControllerTest < ActionDispatch::IntegrationTest
  test "sin sesión manda a entrar" do
    get root_path
    assert_redirected_to entrar_path
  end

  test "entra con usuario y contraseña correctos" do
    post entrar_path, params: { usuario: "Cajera", password: "secreto1" }
    assert_redirected_to root_path
    follow_redirect!
    assert_select "header", /Tienda 1/
    assert_select "li", /Vender en caja/
  end

  test "rechaza contraseña incorrecta y usuarios inactivos" do
    post entrar_path, params: { usuario: "cajera", password: "mal" }
    assert_response :unprocessable_entity
    post entrar_path, params: { usuario: "inactivo", password: "secreto1" }
    assert_response :unprocessable_entity
  end

  test "salir cierra la sesión" do
    post entrar_path, params: { usuario: "admin", password: "secreto1" }
    delete salir_path
    get root_path
    assert_redirected_to entrar_path
  end
end
