# Primer arranque: con la base vacía se crean los roles base, la matriz, el nombre del negocio y
# el administrador, todo en una transacción. Devuelve el administrador ya creado.
module Instalacion
  # folios_modo: por_documento | unico. folios_letra: sucursal (el código de la sucursal va delante),
  # propia (la letra que escriba, folios_venta, para las notas de caja) o ninguna (solo el número).
  def self.instalar!(negocio:, giro:, sucursal:, codigo:, nombre:, usuario:, password:, idioma:, tema: nil, densidad: nil, letra: nil,
                     folios_modo: nil, folios_letra: nil, folios_venta: nil)
    ActiveRecord::Base.transaction do
      Rol.base!
      Modulo.aplicar_giro!(giro)
      matriz = Sucursal.find_or_create_by!(codigo: codigo.to_s.strip.upcase.presence || "MTZ") do |s|
        s.nombre = sucursal.to_s.strip.presence || negocio.to_s.strip.presence || "Matriz"
        s.tipo = "matriz"
      end
      Ajuste.guardar!("negocio.nombre" => negocio) if negocio.present?
      Ajuste.guardar!(ajustes_de_folios(folios_modo, folios_letra, folios_venta))
      Usuario.create!(nombre: nombre, usuario: usuario.to_s.strip.downcase, password: password,
                      rol: Rol.find_by!(nombre: "administrador"), sucursal: matriz,
                      idioma: idioma.to_s.presence_in(Usuario::IDIOMAS) || "en",
                      tema: tema.to_s.presence_in(Usuario::TEMAS) || "claro",
                      densidad: densidad.to_s.presence_in(Usuario::DENSIDADES) || "normal",
                      letra: letra.to_s.presence_in(Usuario::LETRAS) || "normal")
    end
  end

  def self.ajustes_de_folios(modo, letra, venta)
    modo = modo.to_s.presence_in(Folio::MODOS) || "por_documento"
    ajustes = { "folios.modo" => modo, "folios.sucursal" => (letra.to_s == "sucursal" ? "1" : "0") }
    case letra.to_s
    when "sucursal" then ajustes["folios.unico"] = ""                    # MTZ-00001 con numeración única, MTZ-B-00001 por documento
    when "propia"
      ajustes["folios.venta"] = venta.to_s.strip.upcase
      ajustes["folios.unico"] = venta.to_s.strip.upcase if modo == "unico"
    when "ninguna" then Ajuste::SIN_PREFIJO.each { |k| ajustes[k] = "" }
    end
    ajustes
  end
end
