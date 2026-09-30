class Producto < ApplicationRecord
  # Kilo, litro y metro se venden en fracciones (tres decimales); la pieza, entera.
  UNIDADES = %w[kg pieza litro metro].freeze
  UNIDADES_CORTAS = { "kg" => "kg", "pieza" => "pz", "litro" => "l", "metro" => "m" }.freeze
  PLU_INICIAL = 90_000

  has_many :codigos_barras, class_name: "CodigoBarras", dependent: :destroy
  has_many :existencias, dependent: :restrict_with_error
  has_many :precios_sucursal, class_name: "PrecioSucursal", dependent: :destroy
  has_many :promociones, dependent: :destroy

  before_validation :asignar_plu, on: :create

  validates :clave, presence: true, uniqueness: true, length: { maximum: 20 }
  validates :nombre, presence: true
  validates :unidad, inclusion: { in: UNIDADES }
  validates :precio_centavos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :plu, numericality: { only_integer: true, in: 1..99_999 }, uniqueness: true

  scope :activos, -> { where(activo: true) }

  def kg?
    unidad == "kg"
  end

  def fraccionable?
    unidad != "pieza"
  end

  def self.nombre_unidad(unidad) = I18n.t("unidades.#{unidad}", default: unidad)
  def unidad_corta = UNIDADES_CORTAS.fetch(unidad, unidad)

  def precio
    BigDecimal(precio_centavos) / 100
  end

  def precio=(pesos)
    self.precio_centavos = (BigDecimal(pesos.to_s) * 100).round.to_i
  end

  # Precio que rige en una sucursal: el suyo si lo tiene, si no el general.
  def precio_centavos_en(sucursal)
    precios_sucursal.find { |ps| ps.sucursal_id == sucursal.id }&.precio_centavos || precio_centavos
  end

  # Fija (o quita, con nil) el precio de una sucursal.
  def fijar_precio!(sucursal, pesos)
    if pesos.blank?
      precios_sucursal.where(sucursal: sucursal).destroy_all
    else
      precios_sucursal.find_or_initialize_by(sucursal: sucursal).update!(precio_centavos: Dinero.centavos(pesos))
    end
  end

  # Último precio de compra por unidad: el del renglón más reciente en una factura de proveedor
  # abierta. Es lo único que sabe el sistema de costos; el inventario no lleva ninguno.
  def ultimo_costo_centavos
    FacturaProveedorLinea.joins(:factura).where(producto_id: id, facturas_proveedor: { estado: "abierta" })
                         .order("facturas_proveedor.fecha DESC, factura_proveedor_lineas.id DESC").pick(:precio_centavos)
  end

  # Decimales con los que se captura la cantidad: fracciones a 3, piezas enteras.
  def decimales
    fraccionable? ? 3 : 0
  end

  def to_s
    nombre
  end

  private

  def asignar_plu
    return if plu.present?
    self.plu = [ Producto.maximum(:plu).to_i + 1, PLU_INICIAL ].max
  end
end
