# Mínimo y máximo de un producto en una sucursal. Por debajo del mínimo, el reabasto sugiere lo que
# falta para llegar al máximo (o al mínimo, si no hay máximo).
class CrearMinimos < ActiveRecord::Migration[8.1]
  def change
    create_table :minimos do |t|
      t.references :sucursal, null: false, foreign_key: true
      t.references :producto, null: false, foreign_key: true
      t.decimal :minimo, precision: 12, scale: 3, null: false
      t.decimal :maximo, precision: 12, scale: 3
      t.timestamps
      t.check_constraint "minimo >= 0", name: "minimos_minimo"
      t.check_constraint "maximo IS NULL OR maximo >= minimo", name: "minimos_maximo"
    end
    add_index :minimos, %i[sucursal_id producto_id], unique: true
  end
end
