# Cada regla guarda para qué versión del contrato de su gancho se escribió. Si Sakuya cambia lo
# que un gancho recibe o espera, la regla vieja se nota en vez de romperse en silencio.
class AgregarVersionAReglas < ActiveRecord::Migration[8.1]
  def change
    add_column :reglas, :version, :integer, null: false, default: 1
  end
end
