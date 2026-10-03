# Numeración de documentos, por sucursal. El contador va por DOCUMENTO (venta, corte, pedido…),
# nunca por la letra: el prefijo lo elige el negocio en Ajustes › Folios y se puede cambiar sin que
# la numeración se reinicie. También puede llevar una sola numeración corrida para todo.
class Folio < ApplicationRecord
  belongs_to :sucursal

  # Qué documentos numeran y con qué prefijo salen de fábrica.
  DOCUMENTOS = {
    "venta" => "B", "corte" => "C", "devolucion" => "D", "conteo" => "K", "recepcion" => "RC", "traspaso" => "TG", "abono" => "AB", "pedido" => "P"
  }.freeze
  MODOS = %w[por_documento unico].freeze
  PREFIJO = /\A[A-Z0-9]{0,4}\z/

  validates :prefijo, presence: true, inclusion: { in: DOCUMENTOS.keys + [ "unico" ] }
  validates :ultimo, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Siguiente folio de la sucursal para ese documento, atómico: el incremento lo hace la base, no Ruby.
  def self.siguiente!(sucursal, documento)
    documento = documento.to_s
    raise ArgumentError, "documento desconocido: #{documento}" unless DOCUMENTOS.key?(documento)
    contador = unico? ? "unico" : documento
    transaction do
      folio = find_or_create_by!(sucursal: sucursal, prefijo: contador)
      where(id: folio.id).update_all("ultimo = ultimo + 1")
      formatear(prefijo_de(documento), folio.reload.ultimo, codigo: (sucursal.codigo if con_sucursal?))
    end
  end

  def self.unico? = Ajuste["folios.modo"] == "unico"
  # El código de la sucursal va delante (MTZ-B-00001): la letra sale del nombre de la sucursal.
  def self.con_sucursal? = Ajuste["folios.sucursal"] == "1"

  # El prefijo con el que sale el documento: el único si la numeración es corrida, si no el suyo.
  def self.prefijo_de(documento)
    Ajuste[unico? ? "folios.unico" : "folios.#{documento}"].to_s
  end

  def self.formatear(prefijo, numero, codigo: nil)
    [ codigo, prefijo, numero.to_s.rjust(5, "0") ].compact_blank.join("-")
  end
end
