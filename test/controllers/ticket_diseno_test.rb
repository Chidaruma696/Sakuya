require "test_helper"

class TicketDisenoTest < ActionDispatch::IntegrationTest
  setup { post entrar_path, params: { usuario: "admin", password: "secreto1" } }

  test "el diseñador muestra la vista previa y lo guardado sale en el ticket real" do
    get ajustes_seccion_path("negocio")
    assert_response :success
    assert_select "iframe[srcdoc*='B-00042']", true, "la vista previa lleva la venta de muestra"

    logo = "data:image/png;base64," + Base64.strict_encode64("\x89PNG\r\n\x1a\n").to_s
    patch ajustes_ticket_path, params: { ajuste: { "negocio.nombre" => "Abarrotes Doña Rosa", "ticket.lema" => "Desde 1990", "ticket.rfc" => "XAXX010101000",
                                                    "ticket.logo" => logo, "ticket.mostrar_cajero" => "0", "ticket.ancho" => "58", "negocio.pie_ticket" => "Vuelva pronto" } }
    assert_redirected_to ajustes_seccion_path("negocio")
    assert_equal 48, Ajuste.ancho_ticket_mm

    Inventario.mover!(sucursal: sucursales(:tienda), producto: productos(:catsup), tipo: "entrada", cantidad: 5, usuario: usuarios(:admin))
    venta = Caja.cobrar!(sucursal: sucursales(:tienda), usuario: usuarios(:supervisora), clave: "tk1", lineas: [ { producto_id: productos(:catsup).id, cantidad: 1 } ],
                         pagos: [ { forma: "efectivo", monto_centavos: 10_000 } ])
    post entrar_path, params: { usuario: "supervisora", password: "secreto1" }
    get caja_ticket_path(venta)
    assert_response :success
    assert_select ".ticket[style*='width: 48mm']"
    assert_select "[data-ticket='negocio.nombre']", "Abarrotes Doña Rosa"
    assert_select "[data-ticket='ticket.lema']", "Desde 1990"
    assert_select "[data-ticket='ticket.rfc']", "XAXX010101000"
    assert_select "[data-ticket='ticket.mostrar_cajero'].oculto"
    assert_select "[data-ticket='logo'] img[src^='data:image/png']"
    assert_select "[data-ticket='negocio.pie_ticket']", "Vuelva pronto"
  end

  test "un logo que no es imagen o es enorme se rechaza" do
    patch ajustes_ticket_path, params: { ajuste: { "ticket.logo" => "data:text/plain;base64,aG9sYQ==" } }
    assert_match "logo", flash[:alert]
    patch ajustes_ticket_path, params: { ajuste: { "ticket.logo" => "data:image/png;base64," + ("A" * 500_000) } }
    assert_match "logo", flash[:alert]
    assert_equal "", Ajuste["ticket.logo"]
  end
end
