class Movimiento < ApplicationRecord
  ENTRADAS = %w[entrada recepcion devolucion_cliente ajuste_entrada].freeze
  SALIDAS = %w[venta salida merma ajuste_salida].freeze
  TIPOS = (ENTRADAS + SALIDAS).freeze
  NOMBRES = {
    "entrada" => "Entrada", "recepcion" => "Recepción",
    "devolucion_cliente" => "Devolución de cliente", "ajuste_entrada" => "Ajuste (+)",
    "venta" => "Venta", "salida" => "Salida", "merma" => "Merma", "ajuste_salida" => "Ajuste (−)"
  }.freeze

  belongs_to :sucursal
  belongs_to :producto
  belongs_to :referencia, polymorphic: true, optional: true
  belongs_to :usuario

  validates :tipo, inclusion: { in: TIPOS }
  validates :cantidad, numericality: { greater_than: 0 }
  validates :fecha_negocio, presence: true

  # El kardex no se toca: ni updates ni deletes.
  before_update { raise ActiveRecord::ReadOnlyRecord, "los movimientos no se editan" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "los movimientos no se borran" }

  def self.signo(tipo)
    return 1 if ENTRADAS.include?(tipo)
    return -1 if SALIDAS.include?(tipo)
    raise ArgumentError, I18n.t("errores.movimiento.tipo_desconocido", tipo: tipo)
  end

  def entrada?
    ENTRADAS.include?(tipo)
  end

  def nombre_tipo
    I18n.t("movimientos.#{tipo}", default: NOMBRES[tipo])
  end
end
