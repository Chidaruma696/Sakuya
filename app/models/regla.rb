# Un programa en el Lisp de Sakuya enganchado a un punto del sistema. Nunca se edita ni se borra:
# guardar es asentar una versión nueva, y volver atrás es asentar la vieja otra vez.
class Regla < ApplicationRecord
  self.table_name = "reglas"
  # Cada gancho y el módulo que guarda su contrato (su VERSION).
  CONTRATOS = { "tablero" => "Tablero", "corte" => "ReglaCorte", "precio" => "ReglaPrecio", "retiro" => "ReglaRetiro",
                "movimiento" => "ReglaMovimiento", "factura" => "ReglaFactura", "recepcion" => "ReglaRecepcion", "venta" => "ReglaVenta", "credito" => "ReglaCredito" }.freeze
  GANCHOS = CONTRATOS.keys.freeze

  belongs_to :usuario

  validates :gancho, inclusion: { in: GANCHOS }
  validates :codigo, presence: true, length: { maximum: Lisp::LARGO_MAXIMO }

  scope :de, ->(gancho) { where(gancho: gancho).order(id: :desc) }

  # Al guardar, la del contrato de hoy; al restaurar o importar, la que traía.
  attribute :version, :integer, default: nil
  before_validation(on: :create) { self.version ||= self.class.contrato(gancho) if GANCHOS.include?(gancho) }

  before_update { raise ActiveRecord::ReadOnlyRecord, "las reglas no se editan: se asienta otra versión" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "las reglas no se borran" }

  def self.vigente(gancho) = de(gancho).first

  # La versión del contrato que Sakuya tiene hoy para ese gancho.
  def self.contrato(gancho) = CONTRATOS.fetch(gancho).constantize::VERSION

  # Se escribió para un contrato anterior: puede que ya no lea o conteste lo que el gancho espera.
  def vieja? = version < self.class.contrato(gancho)
end
