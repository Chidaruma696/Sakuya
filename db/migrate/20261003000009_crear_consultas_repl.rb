# Lo que se le pregunta al REPL, quién y cuándo. El REPL deja ver todos los datos: que quede rastro.
class CrearConsultasRepl < ActiveRecord::Migration[8.1]
  def change
    create_table :consultas_repl do |t|
      t.references :usuario, null: false, foreign_key: true
      t.references :sucursal, null: false, foreign_key: true
      t.text :texto, null: false
      t.boolean :ok, null: false
      t.datetime :created_at, null: false
    end
    add_index :consultas_repl, :created_at
  end
end
