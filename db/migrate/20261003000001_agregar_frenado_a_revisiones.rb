# Lo que una regla frenó también se revisa: el intento no pasó, pero queda a nombre de quien lo hizo.
class AgregarFrenadoARevisiones < ActiveRecord::Migration[8.1]
  def change
    add_column :revisiones, :frenado, :boolean, default: false, null: false
  end
end
