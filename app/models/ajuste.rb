# Ajustes del sistema, clave/valor, con sus valores de fábrica. Lo que no está guardado vale el
# default; `Ajuste[clave]` devuelve siempre algo.
class Ajuste < ApplicationRecord
  # Claves donde el vacío se guarda tal cual en vez de volver al valor de fábrica.
  SIN_PREFIJO = Folio::DOCUMENTOS.keys.map { |d| "folios.#{d}" }.push("folios.unico").freeze

  DEFAULTS = {
    "negocio.nombre" => "",              # vacío = el nombre de la sucursal
    "negocio.direccion" => "",
    "negocio.telefono" => "",
    "negocio.pie_ticket" => "¡Gracias por su compra!",
    "negocio.moneda" => "MXN",           # código ISO, sale en reportes y exportaciones
    "negocio.simbolo" => "$",            # lo que va pegado a la cifra: $, €, Q, S/…
    "ticket.logo" => "",                 # imagen en data URL (PNG/JPG chico), arriba del ticket
    "ticket.lema" => "",                 # renglón bajo el nombre
    "ticket.rfc" => "",                  # identificación fiscal
    "ticket.leyenda_devoluciones" => "", # vacío = el texto del sistema
    "ticket.mostrar_cajero" => "1",
    "ticket.mostrar_codigo" => "1",      # el código de barras del ticket
    "ticket.ancho" => "80",              # mm de papel: 80 o 58
    "caja.piso_precio" => "50",          # % del catálogo por debajo del cual no se vende ni con permiso
    "caja.limite_gaveta" => "3000",      # pesos, para sucursales nuevas
    "caja.denominaciones" => "1000,500,200,100,50,20,10,5,2,1,0.5", # billetes y monedas para contar la gaveta
    "caja.tope_diferencia" => "0",       # pesos; si |contado − esperado| lo pasa, el cierre pide motivo. 0 = sin tope
    "compras.candado_recibido" => "1", # "1" = facturar más de lo recibido se frena (de fábrica, puesto)
    "folios.modo" => "por_documento",   # o "unico": una sola numeración corrida para todo
    "folios.unico" => "F",
    "folios.sucursal" => "0",            # "1" = el código de la sucursal va delante del folio
    **Folio::DOCUMENTOS.to_h { |doc, letra| [ "folios.#{doc}", letra ] },
    "modulos.compras" => "1",           # módulos opcionales: "1" encendido, "0" apagado (ver Modulo)
    "modulos.almacenes" => "1",
    "modulos.conteos" => "1",
    "modulos.clientes" => "0"           # de fábrica apagado: se enciende en Ajustes › Módulos
  }.freeze
  ENTEROS = %w[caja.piso_precio caja.limite_gaveta caja.tope_diferencia ticket.ancho].freeze
  DENOMINACIONES = /\A\d+(\.\d{1,2})?(,\d+(\.\d{1,2})?)*\z/
  LOGO_MAX = 400_000 # caracteres del data URL (~300 KB de imagen)

  validates :clave, presence: true, uniqueness: true, inclusion: { in: DEFAULTS.keys }

  # Símbolo de la moneda, una consulta por petición.
  def self.simbolo = (Current.simbolo ||= self["negocio.simbolo"])

  # Ancho imprimible del ticket en mm según el papel (80 → 72, 58 → 48).
  def self.ancho_ticket_mm = entero("ticket.ancho") == 58 ? 48 : 72

  def self.[](clave)
    valor = find_by(clave: clave)&.valor
    # Un prefijo de folio vacío es un valor legítimo (solo el número); en lo demás, vacío = de fábrica.
    return valor if !valor.nil? && SIN_PREFIJO.include?(clave)
    valor.presence || DEFAULTS.fetch(clave)
  end

  def self.entero(clave)
    self[clave].to_i
  end

  # Guarda varios de golpe: { "negocio.nombre" => "…" }. Lo vacío vuelve al default.
  def self.guardar!(valores)
    transaction do
      valores.each do |clave, valor|
        next unless DEFAULTS.key?(clave)
        valor = valor.to_s.strip
        raise ArgumentError, I18n.t("errores.ajuste.entero", clave: clave) if ENTEROS.include?(clave) && valor.present? && valor !~ /\A\d+\z/
        raise ArgumentError, I18n.t("errores.ajuste.prefijo", clave: clave) if clave.start_with?("folios.") && !%w[folios.modo folios.sucursal].include?(clave) && (valor = valor.upcase) !~ Folio::PREFIJO
        raise ArgumentError, I18n.t("errores.ajuste.modo_folios") if clave == "folios.modo" && valor.present? && !Folio::MODOS.include?(valor)
        raise ArgumentError, I18n.t("errores.ajuste.denominaciones") if clave == "caja.denominaciones" && valor.present? && (valor = valor.delete(" ")) !~ DENOMINACIONES
        raise ArgumentError, I18n.t("errores.ajuste.logo") if clave == "ticket.logo" && valor.present? && (valor.length > LOGO_MAX || valor !~ %r{\Adata:image/(png|jpeg|gif|webp);base64,})
        registro = find_or_initialize_by(clave: clave)
        valor.blank? && !SIN_PREFIJO.include?(clave) ? registro.destroy : registro.update!(valor: valor)
      end
    end
    Current.simbolo = nil
  end

  def self.todos
    DEFAULTS.keys.index_with { |k| self[k] }
  end
end
