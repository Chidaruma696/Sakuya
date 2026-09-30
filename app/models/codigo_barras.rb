class CodigoBarras < ApplicationRecord
  self.table_name = "codigos_barras"

  belongs_to :producto

  before_validation { self.codigo = CodigoBarras.normalizar(codigo) }

  validates :codigo, presence: true, uniqueness: true, length: { in: 4..32 }

  # Los lectores meten espacios y a veces omiten el cero inicial del UPC-A: aquí solo quedan dígitos.
  def self.normalizar(texto)
    texto.to_s.gsub(/\D/, "")
  end
end
