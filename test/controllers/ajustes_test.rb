require "test_helper"

class AjustesTest < ActionDispatch::IntegrationTest
  test "cada quien guarda idioma, tema, densidad y letra, y el sistema se ve en su idioma" do
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get ajustes_path
    assert_response :ok
    assert_select "h1", "Ajustes"
    assert_select "h2", { text: "Sistema", count: 0 }, "la cajera no administra"
    patch ajustes_preferencias_path, params: { usuario: { idioma: "en", tema: "oscuro", densidad: "compacta", letra: "grande" } }
    assert_redirected_to ajustes_path
    u = usuarios(:cajera).reload
    assert_equal %w[en oscuro compacta grande], [ u.idioma, u.tema, u.densidad, u.letra ]
    follow_redirect!
    assert_select "html[lang=en][data-theme=oscuro][data-densidad=compacta][data-letra=grande]"
    assert_select "h1", "Settings"
    patch ajustes_preferencias_path, params: { usuario: { idioma: "de" } }
    follow_redirect!
    assert_select "h1", "Einstellungen"
    patch ajustes_preferencias_path, params: { usuario: { idioma: "xx" } }
    assert_match "Sprache", flash[:alert]
    patch ajustes_sistema_path, params: { ajuste: { "negocio.nombre" => "X" } }
    assert_response :forbidden
  end

  test "el administrador cambia lo del sistema y se nota en el ticket y el piso de precio" do
    post entrar_path, params: { usuario: "admin", password: "secreto1" }
    patch ajustes_sistema_path, params: { ajuste: { "negocio.nombre" => "Tienda Aurora", "negocio.pie_ticket" => "Vuelva pronto", "caja.piso_precio" => "80", "caja.denominaciones" => "100, 50, 20", "caja.tope_diferencia" => "25" } }
    assert_redirected_to ajustes_seccion_path("modulos")
    assert_equal "Tienda Aurora", Ajuste["negocio.nombre"]
    assert_equal [ 10_000, 5_000, 2_000 ], Corte.denominaciones
    assert_equal 2_500, Corte.tope_diferencia_centavos
    patch ajustes_sistema_path, params: { ajuste: { "caja.denominaciones" => "cien" }, volver: "caja" }
    assert_match "separadas por coma", flash[:alert]
    assert_equal 2_500, Ajuste.entero("caja.tope_diferencia") * 100
    patch ajustes_sistema_path, params: { ajuste: { "caja.tope_diferencia" => "" } }
    assert_equal 0, Ajuste.entero("caja.tope_diferencia"), "vacío vuelve al default"
    patch ajustes_sistema_path, params: { ajuste: { "caja.tope_diferencia" => "abc" } }
    assert_match "entero", flash[:alert]
    patch ajustes_sistema_path, params: { ajuste: { "caja.tope_diferencia" => "25" } }

    # Piso de precio al 80 %: una rebaja al 70 % ya no pasa ni con permiso.
    Inventario.mover!(sucursal: sucursales(:tienda), producto: productos(:catsup), tipo: "entrada", cantidad: 5, usuario: usuarios(:admin))
    e = assert_raises(Caja::Error) do
      Caja.cobrar!(sucursal: sucursales(:tienda), usuario: usuarios(:supervisora), clave: "p1", lineas: [ { producto_id: productos(:catsup).id, cantidad: 1, precio_centavos: 2_940 } ],
                   pagos: [ { forma: "efectivo", monto_centavos: 5_000 } ], autorizador: usuarios(:supervisora))
    end
    assert_match "80 %", e.message
  end
end

class MonedaTest < ActionDispatch::IntegrationTest
  test "el símbolo de la moneda lo pone el negocio y sale en servidor, caja y ticket" do
    assert_equal "$1,234.50", Dinero.pesos(123_450)
    post entrar_path, params: { usuario: "admin", password: "secreto1" }
    patch ajustes_sistema_path, params: { ajuste: { "negocio.moneda" => "GTQ", "negocio.simbolo" => "Q" } }
    Current.reset # en los tests cada petición trae su propio Current y al terminar se restaura el del test
    assert_equal "Q1,234.50", Dinero.pesos(123_450)
    assert_equal "−Q0.50", Dinero.pesos(-50)
    get caja_path
    assert_match 'window.MONEDA = {"simbolo":"Q","codigo":"GTQ"}', response.body
    get ajustes_seccion_path("negocio")
    assert_select "iframe[srcdoc*='Q214.50']"
    patch ajustes_sistema_path, params: { ajuste: { "negocio.moneda" => "", "negocio.simbolo" => "" } }
    Current.reset
    assert_equal "$1.00", Dinero.pesos(100), "vacío vuelve al peso"
  end
end
