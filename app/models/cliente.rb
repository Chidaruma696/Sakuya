# Un cliente del negocio. Por sí solo es un nombre con datos de contacto; lo que importa es lo que
# cuelga de él: su cuenta de crédito y sus pedidos.
class Cliente < ApplicationRecord
  validates :nombre, presence: true
  validates :limite_credito_centavos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :activos, -> { where(activo: true) }

  def limite_credito = BigDecimal(limite_credito_centavos) / 100

  def limite_credito=(pesos)
    self.limite_credito_centavos = Dinero.centavos(pesos)
  end

  def to_s = nombre
end
