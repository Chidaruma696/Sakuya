# Una regla de precio. La caja aplica la mejor vigente para el producto, la sucursal y la cantidad.
class Promocion < ApplicationRecord
  self.table_name = "promociones"

  TIPOS = { "precio" => "Precio especial", "porcentaje" => "Descuento %", "por_cantidad" => "Precio a partir de una cantidad" }.freeze

  belongs_to :producto

  def self.nombre_tipo(tipo) = I18n.t("promociones.tipos.#{tipo}", default: TIPOS[tipo])

  belongs_to :sucursal, optional: true
  has_many :venta_lineas, dependent: :restrict_with_error

  validates :nombre, presence: true
  validates :tipo, inclusion: { in: TIPOS.keys }
  validates :precio_centavos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, if: -> { tipo != "porcentaje" }
  validates :porcentaje, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, if: -> { tipo == "porcentaje" }
  validates :cantidad_minima, numericality: { greater_than: 0 }, if: -> { tipo == "por_cantidad" }
  validate :vigencia_coherente

  scope :activas, -> { where(activa: true) }
  scope :para, ->(producto, sucursal) { activas.where(producto: producto).where(sucursal_id: [ nil, sucursal.id ]) }

  def vigente?(fecha = Date.current)
    activa && (desde.nil? || desde <= fecha) && (hasta.nil? || hasta >= fecha)
  end

  # Precio que resulta para esta cantidad, o nil si no aplica.
  def precio_para(cantidad, catalogo_centavos)
    return nil if cantidad < cantidad_minima
    case tipo
    when "porcentaje" then (catalogo_centavos * (1 - porcentaje / 100)).round.to_i
    else precio_centavos
    end
  end

  # La mejor promoción vigente (el precio más bajo) para producto, sucursal y cantidad.
  def self.mejor(producto, sucursal, cantidad, catalogo_centavos, fecha: Date.current)
    para(producto, sucursal).select { |p| p.vigente?(fecha) }
                            .filter_map { |p| (precio = p.precio_para(cantidad, catalogo_centavos)) && [ precio, p ] }
                            .select { |precio, _| precio < catalogo_centavos }
                            .min_by(&:first)
  end

  def descripcion
    case tipo
    when "precio" then I18n.t("promociones.desc.precio", precio: Dinero.pesos(precio_centavos))
    when "porcentaje" then I18n.t("promociones.desc.porcentaje", pct: porcentaje.to_s("F").sub(/\.0+\z/, ""))
    else I18n.t("promociones.desc.por_cantidad", precio: Dinero.pesos(precio_centavos), desde: cantidad_minima.to_s("F"), unidad: producto.unidad)
    end
  end

  def to_s
    nombre
  end

  private

  def vigencia_coherente
    errors.add(:hasta, I18n.t("errores.promocion.hasta_antes")) if desde && hasta && hasta < desde
  end
end
