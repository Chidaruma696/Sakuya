class ConteoLinea < ApplicationRecord
  belongs_to :conteo, inverse_of: :lineas
  belongs_to :producto

  def contado
    escaneado + manual
  end
end
