class Contador < ApplicationRecord
  self.table_name = "contadores"

  validates :clave, presence: true, uniqueness: true

  # Siguiente valor de la secuencia, atómico.
  def self.siguiente!(clave)
    transaction do
      c = find_or_create_by!(clave: clave)
      where(id: c.id).update_all("ultimo = ultimo + 1")
      c.reload.ultimo
    end
  end

  # Como siguiente!, pero da la vuelta al llegar a `maximo` (1..maximo).
  def self.siguiente_ciclico!(clave, maximo)
    ((siguiente!(clave) - 1) % maximo) + 1
  end
end
