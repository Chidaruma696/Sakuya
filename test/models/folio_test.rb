require "test_helper"

class FoliosPorSucursalTest < ActiveSupport::TestCase
  test "cada sucursal lleva su propia numeración: dos tiendas pueden tener su K-00001" do
    a = Conteo.abrir!(sucursal: sucursales(:matriz), usuario: usuarios(:admin), responsable: usuarios(:admin))
    b = Conteo.abrir!(sucursal: sucursales(:tienda), usuario: usuarios(:supervisora), responsable: usuarios(:cajera))
    assert_equal a.folio, b.folio
    assert_equal "K-00001", b.folio
    assert_raises(ActiveRecord::RecordInvalid) { Conteo.create!(sucursal: sucursales(:tienda), usuario: usuarios(:supervisora), responsable: usuarios(:cajera), folio: "K-00001") }
  end
end

class FolioTest < ActiveSupport::TestCase
  test "numera por sucursal y prefijo, empezando en 1 y con cinco dígitos" do
    assert_equal "B-00001", Folio.siguiente!(sucursales(:matriz), "venta")
    assert_equal "B-00002", Folio.siguiente!(sucursales(:matriz), "venta")
    assert_equal "B-00001", Folio.siguiente!(sucursales(:tienda), "venta")
    assert_equal "TG-00001", Folio.siguiente!(sucursales(:matriz), "traspaso")
  end

  test "no repite folios aunque se pidan muchos seguidos" do
    folios = 50.times.map { Folio.siguiente!(sucursales(:tienda), "venta") }
    assert_equal folios.uniq.size, folios.size
    assert_equal "B-00050", folios.last
  end

  test "el prefijo lo elige el negocio y cambiarlo no reinicia la numeración; sin prefijo sale solo el número" do
    Folio.siguiente!(sucursales(:matriz), "venta")
    Ajuste.guardar!("folios.venta" => "nv")
    assert_equal "NV-00002", Folio.siguiente!(sucursales(:matriz), "venta"), "se guarda en mayúsculas y sigue la cuenta"
    Ajuste.guardar!("folios.venta" => "")
    assert_equal "00003", Folio.siguiente!(sucursales(:matriz), "venta")
    assert_raises(ArgumentError) { Ajuste.guardar!("folios.venta" => "B-1") }
    assert_raises(ArgumentError) { Ajuste.guardar!("folios.venta" => "LARGO") }
  end

  test "el código de la sucursal puede ir delante, y el asistente arma los ajustes según lo elegido" do
    Ajuste.guardar!("folios.sucursal" => "1")
    assert_equal "MTZ-B-00001", Folio.siguiente!(sucursales(:matriz), "venta")
    assert_equal({ "folios.modo" => "por_documento", "folios.sucursal" => "0", "folios.venta" => "NV" }, Instalacion.ajustes_de_folios("por_documento", "propia", "nv"))
    assert_equal "", Instalacion.ajustes_de_folios("unico", "ninguna", nil)["folios.unico"]
    assert_equal({ "folios.modo" => "unico", "folios.sucursal" => "1", "folios.unico" => "" }, Instalacion.ajustes_de_folios("unico", "sucursal", "B"))
  end

  test "con numeración única todos los documentos comparten la cuenta, por sucursal" do
    Ajuste.guardar!("folios.modo" => "unico", "folios.unico" => "F")
    assert_equal "F-00001", Folio.siguiente!(sucursales(:matriz), "venta")
    assert_equal "F-00002", Folio.siguiente!(sucursales(:matriz), "corte")
    assert_equal "F-00003", Folio.siguiente!(sucursales(:matriz), "recepcion")
    assert_equal "F-00001", Folio.siguiente!(sucursales(:tienda), "venta")
    assert_raises(ArgumentError) { Ajuste.guardar!("folios.modo" => "raro") }
    Ajuste.guardar!("folios.modo" => "por_documento")
    assert_equal "B-00001", Folio.siguiente!(sucursales(:matriz), "venta"), "al volver, cada documento retoma su propia cuenta"
  end
end
