# Mínimo y máximo de un producto en una sucursal, y lo que hace falta para reabastecerla.
class Minimo < ApplicationRecord
  belongs_to :sucursal
  belongs_to :producto

  validates :minimo, numericality: { greater_than_or_equal_to: 0 }
  validates :maximo, numericality: { greater_than_or_equal_to: :minimo }, allow_nil: true
  validates :producto_id, uniqueness: { scope: :sucursal_id }

  def tope = maximo || minimo

  # Lo que le falta a una sucursal: [[producto, cantidad]] de lo que está por debajo de su mínimo,
  # para llegar al máximo. Las piezas se redondean hacia arriba.
  def self.sugerido(sucursal)
    existencias = Existencia.where(sucursal: sucursal).pluck(:producto_id, :cantidad).to_h
    where(sucursal: sucursal).includes(:producto).filter_map do |m|
      next unless m.producto.activo
      hay = existencias.fetch(m.producto_id, 0)
      next if hay >= m.minimo
      falta = m.tope - hay
      falta = falta.ceil unless m.producto.fraccionable?
      [ m.producto, falta.round(3) ] if falta.positive?
    end.sort_by { |p, _| p.nombre }
  end

  # Guarda los mínimos de una sucursal de golpe: { producto_id => { minimo:, maximo: } }. Un mínimo
  # vacío quita la fila.
  def self.guardar!(sucursal, valores)
    transaction do
      valores.each do |producto_id, v|
        fila = find_or_initialize_by(sucursal: sucursal, producto_id: producto_id)
        if v[:minimo].blank?
          fila.destroy if fila.persisted?
          next
        end
        fila.update!(minimo: v[:minimo], maximo: v[:maximo].presence)
      end
    end
  end
end
