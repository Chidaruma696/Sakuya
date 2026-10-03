# Ventas que la caja hizo sin conexión y subió después: cuándo se hicieron de verdad, y la marca
# para que se distingan en los reportes y en la revisión.
class AgregarFueraDeLineaAVentas < ActiveRecord::Migration[8.1]
  def change
    add_column :ventas, :fuera_de_linea, :boolean, null: false, default: false
    add_column :ventas, :vendida_en, :datetime
  end
end
