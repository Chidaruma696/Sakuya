# Un pedido abierto aparta en su sucursal lo que pide (salvo que se guarde sin apartar, para
# pedidos a futuro): eso no se vende ni se traspasa hasta que el pedido se cobra o se cancela.
class AgregarApartarAPedidos < ActiveRecord::Migration[8.1]
  def change
    add_column :pedidos, :apartar, :boolean, null: false, default: true
  end
end
