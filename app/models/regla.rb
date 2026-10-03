# Un programa en el Lisp de Sakuya enganchado a un punto del sistema. Nunca se edita ni se borra:
# guardar es asentar una versión nueva, y volver atrás es asentar la vieja otra vez.
class Regla < ApplicationRecord
  self.table_name = "reglas"
  GANCHOS = %w[tablero corte precio retiro movimiento].freeze

  belongs_to :usuario

  validates :gancho, inclusion: { in: GANCHOS }
  validates :codigo, presence: true, length: { maximum: Lisp::LARGO_MAXIMO }

  scope :de, ->(gancho) { where(gancho: gancho).order(id: :desc) }

  before_update { raise ActiveRecord::ReadOnlyRecord, "las reglas no se editan: se asienta otra versión" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "las reglas no se borran" }

  def self.vigente(gancho) = de(gancho).first
end
