# Módulo de clientes: el catálogo. La cuenta (crédito y abonos) y los pedidos llegan después.
class CrearClientes < ActiveRecord::Migration[8.1]
  def change
    create_table :clientes do |t|
      t.string :nombre, null: false
      t.string :telefono
      t.string :rfc
      t.string :direccion
      t.string :notas
      # Lo lee la regla de crédito como (limit); Sakuya no hace nada con él por su cuenta.
      t.integer :limite_credito_centavos, null: false, default: 0
      t.boolean :activo, null: false, default: true
      t.timestamps
    end
    add_index :clientes, :nombre
  end
end
