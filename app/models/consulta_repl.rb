# Una pregunta al REPL: quién, desde qué sucursal, qué escribió y si corrió. Solo inserción.
class ConsultaRepl < ApplicationRecord
  self.table_name = "consultas_repl"

  belongs_to :usuario
  belongs_to :sucursal

  validates :texto, presence: true

  before_update { raise ActiveRecord::ReadOnlyRecord, "la bitácora del REPL no se edita" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "la bitácora del REPL no se borra" }
end
