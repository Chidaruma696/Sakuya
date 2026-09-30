# Módulos que se encienden o apagan por negocio (el mapa completo está en docs/arquitectura.md).
# Caja, inventario, administración y ajustes van siempre; el resto depende del giro elegido al
# arrancar y se puede cambiar después en Ajustes. Cada módulo es un conjunto aparte: sus tablas,
# sus permisos, su pestaña. DEPENDE y ALGUNO quedan listos para cuando un módulo cuelgue de otro.
module Modulo
  OPCIONALES = %w[compras almacenes conteos].freeze
  DEPENDE = {}.freeze
  # Necesita al menos uno de la lista encendido.
  ALGUNO = {}.freeze
  # Prefijos de permiso que cuelgan de cada módulo (los demás permisos van siempre).
  PERMISOS = { "compras" => %w[compras], "almacenes" => %w[almacenes], "conteos" => %w[conteos] }.freeze
  # Preset por giro.
  GIROS = {
    "tienda" => %w[compras conteos],
    "varias_sucursales" => %w[compras almacenes conteos],
    "todo" => OPCIONALES
  }.freeze

  def self.activo?(clave)
    return true unless OPCIONALES.include?(clave.to_s)
    activos.include?(clave.to_s)
  end

  # Se lee una vez por petición (Current) para no consultar la tabla en cada botón de la cinta.
  def self.activos
    Current.modulos ||= OPCIONALES.select { |m| Ajuste["modulos.#{m}"] == "1" }
  end

  def self.permiso_activo?(clave)
    prefijo = clave.to_s.split(".").first
    modulo = PERMISOS.find { |_, prefijos| prefijos.include?(prefijo) }&.first
    modulo.nil? || activo?(modulo)
  end

  # Al instalar no hay trabajo abierto que cuidar.
  def self.aplicar_giro!(giro)
    guardar!(GIROS.fetch(giro.to_s, OPCIONALES), comprobar: false)
  end

  # Lo que un módulo necesita encendido, y quiénes lo necesitan a él.
  def self.necesita(modulo) = DEPENDE.fetch(modulo.to_s, [])
  def self.alguno(modulo) = ALGUNO.fetch(modulo.to_s, [])
  def self.dependientes(modulo) = DEPENDE.select { |_, base| base.include?(modulo.to_s) }.keys
  # Quiénes tendrían a `modulo` como su última base encendida dentro de `activos`.
  def self.dependientes_alguno(modulo, activos)
    ALGUNO.select { |d, opciones| activos.include?(d) && opciones.include?(modulo.to_s) && (opciones & activos).empty? }.keys
  end

  def self.nombre(modulo) = I18n.t("modulos.#{modulo}.nombre")

  # Enciende los de la lista y apaga el resto. Encender arrastra lo que necesita; apagar una base
  # que otro encendido necesita se rechaza nombrándolo, y apagar algo con trabajo abierto también.
  def self.guardar!(lista, comprobar: true)
    nuevos = (Array(lista).map(&:to_s) & OPCIONALES)
    viejos = activos
    (nuevos - viejos).each do |m|
      nuevos |= necesita(m)
      nuevos |= [ alguno(m).first ] if alguno(m).any? && (alguno(m) & nuevos).empty?
    end
    (viejos - nuevos).each do |m|
      quienes = (dependientes(m) & nuevos) | dependientes_alguno(m, nuevos)
      raise ArgumentError, I18n.t("errores.modulo.con_dependientes", modulo: nombre(m), dependientes: quienes.map { |d| nombre(d) }.join(", ")) if quienes.any?
      comprobar_apagable!(m) if comprobar
    end
    Ajuste.guardar!(OPCIONALES.to_h { |m| [ "modulos.#{m}", nuevos.include?(m) ? "1" : "0" ] })
    Current.modulos = nil
  end

  def self.comprobar_apagable!(modulo)
    abierto = case modulo
    when "conteos" then Conteo.abiertos.exists?
    when "almacenes" then Sucursal.activas.almacenes.exists?
    end
    raise ArgumentError, I18n.t("errores.modulo.con_trabajo_abierto", modulo: I18n.t("modulos.#{modulo}.nombre")) if abierto
  end
end
