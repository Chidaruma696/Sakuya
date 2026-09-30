# Los programas en Lisp de cada negocio. Solo inserción: cambiar una regla es asentar una versión
# nueva, y la vigente es la última de su gancho.
class CrearReglas < ActiveRecord::Migration[8.1]
  def change
    create_table :reglas do |t|
      t.string :gancho, null: false
      t.text :codigo, null: false
      t.references :usuario, null: false, foreign_key: true
      t.datetime :created_at, null: false
    end
    add_index :reglas, [ :gancho, :id ]
  end
end
