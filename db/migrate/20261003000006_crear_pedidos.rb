# Pedidos de clientes: se apuntan, se preparan y se cobran en la caja cuando el cliente pasa por
# ellos (o se le mandan). El precio se pone al cobrar, con las reglas de siempre.
class CrearPedidos < ActiveRecord::Migration[8.1]
  def change
    create_table :pedidos do |t|
      t.references :cliente, null: false, foreign_key: true
      t.references :sucursal, null: false, foreign_key: true
      t.references :usuario, null: false, foreign_key: true
      t.references :venta, foreign_key: true
      t.string :folio, null: false
      t.string :estado, null: false, default: "abierto"
      t.date :fecha_entrega
      t.string :notas
      t.string :motivo_cancelacion
      t.timestamps
      t.check_constraint "estado IN ('abierto', 'entregado', 'cancelado')", name: "pedidos_estado"
    end
    add_index :pedidos, %i[sucursal_id folio], unique: true
    create_table :pedido_lineas do |t|
      t.references :pedido, null: false, foreign_key: true
      t.references :producto, null: false, foreign_key: true
      t.decimal :cantidad, precision: 12, scale: 3, null: false
      t.check_constraint "cantidad > 0", name: "pedido_lineas_cantidad"
    end
  end
end
