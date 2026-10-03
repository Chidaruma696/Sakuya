# Cómo imprime los tickets cada sucursal: con el navegador (como siempre), en una térmica de red
# (el servidor le habla a su puerto, casi siempre el 9100) o en una térmica por cable desde el
# navegador (Web Serial).
class AgregarImpresoraASucursales < ActiveRecord::Migration[8.1]
  def change
    add_column :sucursales, :impresora, :string, null: false, default: "navegador"
    add_column :sucursales, :impresora_red, :string
  end
end
