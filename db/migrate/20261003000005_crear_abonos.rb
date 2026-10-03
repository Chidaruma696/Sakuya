# Lo que un cliente paga a su cuenta. Entra a la caja abierta y baja su saldo.
class CrearAbonos < ActiveRecord::Migration[8.1]
  def change
    create_table :abonos do |t|
      t.references :cliente, null: false, foreign_key: true
      t.references :sucursal, null: false, foreign_key: true
      t.references :corte, null: false, foreign_key: true
      t.references :usuario, null: false, foreign_key: true
      t.string :folio, null: false
      t.integer :monto_centavos, null: false
      t.string :forma, null: false
      t.string :notas
      t.datetime :created_at, null: false
      t.check_constraint "monto_centavos > 0", name: "abonos_monto"
      t.check_constraint "forma IN ('efectivo', 'transferencia', 'deposito')", name: "abonos_forma"
    end
    add_index :abonos, %i[sucursal_id folio], unique: true
  end
end
