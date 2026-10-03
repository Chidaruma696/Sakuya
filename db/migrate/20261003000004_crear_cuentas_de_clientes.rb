# La cuenta de cada cliente: vender a cuenta carga, abonar y devolver descargan. Solo inserción;
# el saldo es la suma de los montos con signo.
class CrearCuentasDeClientes < ActiveRecord::Migration[8.1]
  def change
    add_reference :ventas, :cliente, foreign_key: true
    create_table :movimientos_credito do |t|
      t.references :cliente, null: false, foreign_key: true
      t.references :sucursal, null: false, foreign_key: true
      t.references :usuario, null: false, foreign_key: true
      t.string :tipo, null: false
      t.integer :monto_centavos, null: false
      t.date :fecha, null: false
      t.references :referencia, polymorphic: true
      t.string :motivo
      t.datetime :created_at, null: false
    end
    add_index :movimientos_credito, %i[cliente_id fecha id]
    add_check_constraint :movimientos_credito, "tipo IN ('cargo', 'abono', 'devolucion')", name: "movimientos_credito_tipo"
    # Vender a cuenta es una forma de pago más; no mete dinero a la gaveta.
    remove_check_constraint :pagos, "forma IN ('efectivo', 'transferencia', 'deposito')", name: "pagos_forma"
    add_check_constraint :pagos, "forma IN ('efectivo', 'transferencia', 'deposito', 'credito')", name: "pagos_forma"
    # De una devolución, lo que bajó la deuda del cliente en vez de salir de la gaveta.
    add_column :devoluciones, :a_cuenta_centavos, :integer, null: false, default: 0
  end
end
