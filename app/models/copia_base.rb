# Pasa todos los datos de esta base a otra vacía con el mismo esquema (por ejemplo, de SQLite a
# PostgreSQL cuando el negocio crece). Copia tabla por tabla, de las que no dependen de nadie a las
# que dependen, ajusta los contadores de id y al final compara cuántas filas hay de cada lado.
#
#   bin/rails "sakuya:copiar_base[postgres://usuario:clave@servidor/sakuya]"
module CopiaBase
  class Error < StandardError; end

  LOTE = 1_000
  SIN_COPIAR = %w[schema_migrations ar_internal_metadata].freeze

  # Un modelo suelto para leer y escribir cualquier tabla del destino.
  class Destino < ActiveRecord::Base
    self.abstract_class = true
  end

  def self.copiar!(url, origen: ActiveRecord::Base.connection, avisar: ->(_) { })
    Destino.establish_connection(url)
    destino = Destino.connection
    tablas = ordenar(origen.tables - SIN_COPIAR, origen)
    faltan = tablas - destino.tables
    raise Error, "al destino le faltan tablas (carga antes el esquema): #{faltan.join(", ")}" if faltan.any?
    llenas = tablas.select { |t| destino.select_value("SELECT COUNT(*) FROM #{destino.quote_table_name(t)}").to_i.positive? }
    raise Error, "el destino ya tiene datos en: #{llenas.join(", ")}" if llenas.any?

    destino.transaction do
      tablas.each do |tabla|
        total = copiar_tabla(tabla, origen, destino)
        avisar.("#{tabla}: #{total}")
      end
    end
    reiniciar_secuencias(tablas, destino)
    comparar(tablas, origen, destino)
  ensure
    Destino.remove_connection
  end

  # De las que no dependen de nadie a las que dependen (por sus llaves foráneas).
  def self.ordenar(tablas, conexion)
    depende = tablas.to_h { |t| [ t, conexion.foreign_keys(t).map(&:to_table).uniq & tablas - [ t ] ] }
    orden = []
    until depende.empty?
      listas = depende.select { |_, deps| (deps - orden).empty? }.keys
      raise Error, "hay un ciclo de llaves entre: #{depende.keys.join(", ")}" if listas.empty?
      orden.concat(listas.sort)
      listas.each { |t| depende.delete(t) }
    end
    orden
  end

  def self.copiar_tabla(tabla, origen, destino)
    columnas = origen.columns(tabla).map(&:name)
    orden = columnas.include?("id") ? " ORDER BY id" : ""
    total = 0
    desde = 0
    loop do
      filas = origen.select_all("SELECT * FROM #{origen.quote_table_name(tabla)}#{orden} LIMIT #{LOTE} OFFSET #{desde}").to_a
      break if filas.empty?
      modelo = Class.new(Destino) { self.table_name = tabla }
      modelo.reset_column_information
      modelo.insert_all!(filas.map { |f| f.slice(*columnas) }, record_timestamps: false)
      total += filas.size
      desde += LOTE
    end
    total
  end

  # En PostgreSQL los ids salen de secuencias: que sigan después del último copiado.
  def self.reiniciar_secuencias(tablas, destino)
    return unless destino.respond_to?(:reset_pk_sequence!)
    tablas.each { |t| destino.reset_pk_sequence!(t) if destino.columns(t).any? { |c| c.name == "id" } }
  end

  def self.comparar(tablas, origen, destino)
    distintas = tablas.filter_map do |t|
      a = origen.select_value("SELECT COUNT(*) FROM #{origen.quote_table_name(t)}").to_i
      b = destino.select_value("SELECT COUNT(*) FROM #{destino.quote_table_name(t)}").to_i
      "#{t} (#{a} → #{b})" if a != b
    end
    raise Error, "no cuadran: #{distintas.join(", ")}" if distintas.any?
    tablas.size
  end

  private_class_method :ordenar, :copiar_tabla, :reiniciar_secuencias, :comparar
end
