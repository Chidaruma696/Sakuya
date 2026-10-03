require "test_helper"

class CajaControllerTest < ActionDispatch::IntegrationTest
  setup do
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    @tienda = sucursales(:tienda)
    Inventario.mover!(sucursal: @tienda, producto: productos(:catsup), tipo: "entrada", cantidad: 5, usuario: usuarios(:cajera))
    @pesada = { producto_id: productos(:pechuga).id, cantidad: "2.000" }
    Inventario.mover!(sucursal: @tienda, producto: productos(:pechuga), tipo: "entrada", cantidad: 2, usuario: usuarios(:cajera))
  end

  test "la cajera baja un precio sin permiso: no se cobra y el intento queda reportado; la supervisora sí cobra y queda por revisar" do
    rebaja = { lineas: [ { producto_id: productos(:catsup).id, cantidad: 2, precio_centavos: 3_000 } ].to_json,
               pagos: [ { forma: "efectivo", monto_centavos: 6_000 } ].to_json }
    post caja_cobrar_path, params: rebaja.merge(clave: "rebaja"), headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_match "Así no se cobra", response.parsed_body["error"]
    assert_nil Venta.find_by(clave: "rebaja")
    r = Revision.last
    assert r.frenado?
    assert_equal 2_400, r.valor_centavos, "2 × (42.00 − 30.00)"
    assert_match "Intento frenado en el corte", r.descripcion
    get revisiones_path
    assert_response :forbidden, "la cajera no revisa"
    delete salir_path
    post entrar_path, params: { usuario: "supervisora", password: "secreto1" }
    post caja_cobrar_path, params: rebaja.merge(clave: "rebaja2"), headers: { "Accept" => "application/json" }
    assert_response :ok
    venta = Venta.find_by!(clave: "rebaja2")
    assert_equal usuarios(:supervisora), venta.lineas.first.autorizado_por
    assert_equal venta.lineas.first, Revision.last.revisable
    delete salir_path
    post entrar_path, params: { usuario: "admin", password: "secreto1" }
    get revisiones_path(sucursal_id: "todas")
    assert_select "td", /Precio bajado en B-/
    assert_select "td", /Intento frenado/
  end

  test "vender: escanea, cobra por JSON, imprime ticket y aparece en ventas" do
    get caja_path
    assert_select "input[data-pos-target=codigo]"
    get caja_escanear_path(codigo: "PECH"), headers: { "Accept" => "application/json" }
    assert_equal productos(:pechuga).id, response.parsed_body["producto_id"]
    assert_equal "kg", response.parsed_body["unidad"]
    get caja_escanear_path(codigo: "CATS"), headers: { "Accept" => "application/json" }
    assert_equal "pieza", response.parsed_body["unidad"]
    get caja_escanear_path(codigo: "nada"), headers: { "Accept" => "application/json" }
    assert_response :not_found

    post caja_cobrar_path, params: { clave: "abc", lineas: [ @pesada, { producto_id: productos(:catsup).id, cantidad: 1 } ].to_json,
                                     pagos: [ { forma: "efectivo", monto_centavos: 50_000 } ].to_json }, headers: { "Accept" => "application/json" }
    assert_response :ok
    venta = Venta.last
    assert_equal 30_000, venta.total_centavos
    assert_equal caja_ticket_path(venta, imprimir: 1), response.parsed_body["url"]
    get caja_ticket_path(venta)
    assert_select "svg"
    assert_match "TOTAL", response.body
    get caja_ventas_path
    assert_select "td", /#{venta.folio}/
  end

  test "sin caja abierta no cobra; el corte se abre, la cajera sin permiso no retira (queda reportado), la supervisora sí, y se cierra" do
    cortes(:tienda_abierto).update!(estado: "cerrado")
    post caja_cobrar_path, params: { clave: "x", lineas: [ { producto_id: productos(:catsup).id, cantidad: 1 } ].to_json, pagos: [ { forma: "efectivo", monto_centavos: 5_000 } ].to_json }, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_match "no hay caja abierta", response.parsed_body["error"]
    post caja_abrir_path, params: { fondo: "500.00" }
    assert_redirected_to caja_path
    corte = Corte.abierto_en(@tienda)
    assert_equal 50_000, corte.fondo_centavos
    get caja_corte_path
    assert_match "el retiro se frena", response.body
    post caja_retirar_path, params: { monto: "100", motivo: "caja fuerte" }
    assert_match "Así no se retira", flash[:alert]
    assert_equal 0, corte.retiros.count, "la cajera no tiene caja.retirar: se frena"
    reporte = Revision.last
    assert reporte.frenado?
    assert_equal [ corte, 10_000 ], [ reporte.revisable, reporte.valor_centavos ]
    assert_match "Retiro de $100.00 frenado (caja fuerte)", reporte.motivo
    post caja_retirar_path, params: { monto: "100", motivo: "caja fuerte" }
    assert_equal 1, Revision.count, "el mismo intento no se reporta dos veces"
    post entrar_path, params: { usuario: "supervisora", password: "secreto1" }
    2.times { post caja_retirar_path, params: { monto: "100", motivo: "caja fuerte" } }
    assert_equal 20_000, corte.retiros.sum(:monto_centavos)
    assert_equal [ usuarios(:supervisora) ], corte.retiros.map(&:autorizado_por).uniq
    assert_equal 1, Revision.count, "con permiso, de fábrica, no hay nada que revisar"
    post caja_cerrar_path, params: { contado: "300.00" }
    assert_redirected_to caja_resumen_path(corte)
    assert_equal 0, corte.reload.diferencia_centavos
    follow_redirect!
    assert_select "div.centro", /#{corte.folio}/
    assert_match "Retiros", response.body
    assert_match "caja fuerte", response.body
    assert_match "1 pendiente", response.body
    get caja_corte_path
    assert_select "td", /#{corte.folio}/
    assert_select "a[href=?]", caja_resumen_path(corte)
  end

  test "cerrar contando billetes; con tope, una diferencia grande frena a la cajera, se reporta y solo la supervisora cierra" do
    corte = cortes(:tienda_abierto)
    get caja_corte_path
    assert_select "input[name='denominacion[50000]']"
    assert_select "[data-gaveta-target=motivo]", { count: 0 }, "sin tope no hay motivo que pedir"
    Ajuste.guardar!("caja.tope_diferencia" => "50")
    get caja_corte_path
    assert_select "[data-gaveta-target=motivo]"
    assert_match "No se puede cerrar así", response.body
    post caja_cerrar_path, params: { denominacion: { "20000" => "1", "10000" => "2" }, motivo: "faltó un billete" }
    assert_match "pasa del tope ($50.00). Así no se cierra", flash[:alert], "la cajera no tiene caja.diferencia: ni con motivo"
    assert corte.reload.abierto?
    reporte = Revision.last
    assert_equal [ corte, usuarios(:cajera), 10_000 ], [ reporte.revisable, reporte.usuario, reporte.valor_centavos ]
    assert_match "contó $400.00", reporte.motivo
    assert_match "Intento frenado en el corte", reporte.descripcion
    assert reporte.frenado?
    post caja_cerrar_path, params: { contado: "400.00" }
    assert_equal 1, Revision.count, "contar lo mismo otra vez no repite el reporte"
    post entrar_path, params: { usuario: "supervisora", password: "secreto1" }
    post caja_cerrar_path, params: { denominacion: { "20000" => "1", "10000" => "2" } }
    assert_match "escribe el motivo", flash[:alert]
    post caja_cerrar_path, params: { denominacion: { "20000" => "1", "10000" => "2" }, motivo: "faltó un billete" }
    assert_redirected_to caja_resumen_path(corte)
    assert_match "queda por revisar", flash[:notice]
    assert_equal 40_000, corte.reload.contado_centavos
    assert_equal(-10_000, corte.diferencia_centavos)
    assert_equal({ "20000" => 1, "10000" => 2 }, corte.desglose)
    r = Revision.last
    assert_equal corte, r.revisable
    assert_equal 10_000, r.valor_centavos
    assert_match corte.folio, r.descripcion
    get caja_corte_path
    assert_select "td[title='1 × $200.00, 2 × $100.00']"
  end

  test "cerrar con el total tecleado y con diferencia dentro del tope no pide nada" do
    Ajuste.guardar!("caja.tope_diferencia" => "50")
    post caja_cerrar_path, params: { contado: "480.00" }
    assert_redirected_to caja_resumen_path(cortes(:tienda_abierto))
    assert_no_match "por revisar", flash[:notice]
    assert_equal(-2_000, cortes(:tienda_abierto).reload.diferencia_centavos)
    assert_equal 0, Revision.count
  end

  test "la regla del corte rechaza: la cajera no cierra, la supervisora sí y queda por revisar" do
    corte = cortes(:tienda_abierto)
    Regla.create!(gancho: "corte", codigo: '(if (< (difference) 0) (reject "falta dinero") (allow))', usuario: usuarios(:admin))
    get caja_corte_path
    assert_match "su propia regla para el cierre", response.body, "con regla propia el motivo se enseña siempre"
    post caja_cerrar_path, params: { contado: "490.00", motivo: "ni modo" }
    assert_match "falta dinero. Así no se cierra", flash[:alert]
    assert corte.reload.abierto?
    post entrar_path, params: { usuario: "supervisora", password: "secreto1" }
    post caja_cerrar_path, params: { contado: "490.00" }
    assert_match "falta dinero: escribe el motivo", flash[:alert]
    post caja_cerrar_path, params: { contado: "490.00", motivo: "se contó dos veces" }
    assert_redirected_to caja_resumen_path(corte)
    assert_equal "se contó dos veces", Revision.last.motivo
  end

  test "si la regla del corte truena decide la de fábrica y el fallo queda en revisión" do
    Regla.create!(gancho: "corte", codigo: "(no-existe)", usuario: usuarios(:admin))
    post caja_cerrar_path, params: { contado: "500.00" }
    assert_redirected_to caja_resumen_path(cortes(:tienda_abierto))
    assert_match "queda por revisar", flash[:notice]
    assert_match "La regla del corte falló", Revision.last.motivo
    Ajuste.guardar!("caja.tope_diferencia" => "50")
    post caja_abrir_path, params: { fondo: "500" }
    post caja_cerrar_path, params: { contado: "100.00" }
    assert_match "Así no se cierra", flash[:alert], "la de fábrica frena"
    assert_match(/Intento de cierre frenado.*\nLa regla del corte falló/m, Revision.last.motivo)
  end

  test "con el módulo de clientes la caja pide el cliente y lo que va a cuenta" do
    get caja_path
    assert_select "[data-pos-target=credito]", 0
    Modulo.guardar!(Modulo::OPCIONALES, comprobar: false)
    lupita = Cliente.create!(nombre: "Fonda Lupita")
    Regla.create!(gancho: "credito", codigo: "(allow)", usuario: usuarios(:admin))
    get caja_path
    assert_select "select[data-pos-target=cliente] option", /Fonda Lupita/
    assert_select "[data-pos-target=credito]"
    post caja_cobrar_path, params: { clave: "fiado", cliente_id: lupita.id, lineas: [ { producto_id: productos(:catsup).id, cantidad: 1 } ].to_json,
                                     pagos: [ { forma: "credito", monto_centavos: 4_200 } ].to_json }, headers: { "Accept" => "application/json" }
    assert_response :ok
    assert_equal 4_200, lupita.saldo_centavos
  end

  test "el ticket se baja en ESC/POS para una térmica" do
    venta = Caja.cobrar!(sucursal: @tienda, usuario: usuarios(:cajera), clave: "t", lineas: [ { producto_id: productos(:catsup).id, cantidad: 1 } ],
                         pagos: [ { forma: "efectivo", monto_centavos: 5_000 } ])
    get caja_ticket_path(venta)
    assert_select "a[href=?]", caja_escpos_path(venta, bajar: 1)
    get caja_escpos_path(venta, bajar: 1)
    assert_equal "application/octet-stream", response.media_type
    assert_match "#{venta.folio}.bin", response.headers["Content-Disposition"]
    assert response.body.b.start_with?("\e@".b)
  end

  test "el ticket se imprime según la impresora de la sucursal: navegador, red o cable" do
    venta = Caja.cobrar!(sucursal: @tienda, usuario: usuarios(:cajera), clave: "i", lineas: [ { producto_id: productos(:catsup).id, cantidad: 1 } ],
                         pagos: [ { forma: "efectivo", monto_centavos: 5_000 } ])
    get caja_ticket_path(venta, imprimir: 1)
    assert_match "window.print()", response.body
    assert_select "#termica", 0
    @tienda.update!(impresora: "serial")
    get caja_ticket_path(venta, imprimir: 1)
    assert_select "#termica"
    assert_match "navigator.serial", response.body
    servidor = TCPServer.new("127.0.0.1", 0)
    recibido = +"".b
    hilo = Thread.new { c = servidor.accept; recibido << c.read; c.close }
    @tienda.update!(impresora: "red", impresora_red: "127.0.0.1:#{servidor.addr[1]}")
    post caja_imprimir_path(venta), headers: { "Accept" => "application/json" }
    hilo.join(3)
    assert_response :ok
    assert recibido.start_with?("\e@".b)
    assert_includes recibido, venta.folio
    servidor.close
    post caja_imprimir_path(venta), headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_match "no contesta", response.parsed_body["error"]
  end

  test "devolución solo con ticket" do
    venta = Caja.cobrar!(sucursal: @tienda, usuario: usuarios(:cajera), clave: "v1", lineas: [ @pesada ], pagos: [ { forma: "efectivo", monto_centavos: 30_000 } ])
    get caja_devolucion_path(codigo: "0000000000000")
    assert_match "Sin ticket", response.body
    get caja_devolucion_path(codigo: venta.folio)
    assert_select "strong", venta.folio
    linea = venta.lineas.first
    post caja_devolver_path, params: { venta_id: venta.id, lineas: { linea.id => "2" }, motivo: "" }
    assert_redirected_to caja_devolucion_path(codigo: nil)
    post caja_devolver_path, params: { venta_id: venta.id, lineas: { linea.id => "2" }, motivo: "mal olor" }
    assert_redirected_to caja_ventas_path
    assert_equal "devuelta", venta.reload.estado
  end
end
