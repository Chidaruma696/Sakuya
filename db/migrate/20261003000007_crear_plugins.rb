# Plugins en Lisp: un archivo que trae funciones compartidas para las reglas, informes para el
# REPL y traducciones de la interfaz. Se guarda tal cual llegó; se lee, nunca se ejecuta al instalar.
class CrearPlugins < ActiveRecord::Migration[8.1]
  def change
    create_table :plugins do |t|
      t.string :identificador, null: false
      t.string :nombre, null: false
      t.string :version
      t.string :autor
      t.string :descripcion
      t.text :codigo, null: false
      t.boolean :activo, null: false, default: false
      t.references :usuario, null: false, foreign_key: true
      t.timestamps
    end
    add_index :plugins, :identificador, unique: true
  end
end
