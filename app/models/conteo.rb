# Conteo físico: el supervisor escanea las piezas (y teclea lo que va en fracciones), el sistema
# compara contra la existencia y, al cerrar, el conteo manda: se ajusta el inventario y el
# faltante se le carga al responsable.
class Conteo < ApplicationRecord
  belongs_to :sucursal
  belongs_to :usuario
  belongs_to :responsable, class_name: "Usuario"
  has_many :lineas, class_name: "ConteoLinea", dependent: :destroy, inverse_of: :conteo
  has_many :cargos, dependent: :restrict_with_error

  before_validation :asignar_folio, on: :create

  validates :folio, presence: true, uniqueness: { scope: :sucursal_id }
  validates :estado, inclusion: { in: %w[abierto cerrado] }
  validates :alcance, inclusion: { in: %w[total parcial] }

  scope :abiertos, -> { where(estado: "abierto") }
  scope :cerrados, -> { where(estado: "cerrado") }

  def abierto? = estado == "abierto"
  def parcial? = alcance == "parcial"

  # Total: todo lo que hay en la sucursal. Parcial: solo `productos` (una lista o toda una línea),
  # con existencia o sin ella, para poder contar sobrantes; lo demás no se toca al cerrar.
  def self.abrir!(sucursal:, usuario:, responsable:, productos: nil)
    raise ArgumentError, I18n.t("errores.conteo.ya_abierto", sucursal: sucursal.nombre) if abiertos.exists?(sucursal: sucursal)
    raise ArgumentError, I18n.t("errores.conteo.parcial_vacio") if productos && productos.empty?
    transaction do
      c = create!(sucursal: sucursal, usuario: usuario, responsable: responsable, alcance: productos ? "parcial" : "total")
      if productos
        productos.each { |p| c.lineas.create!(producto: p, sistema: Existencia.de(sucursal, p)) }
      else
        Existencia.where(sucursal: sucursal).where("cantidad > 0").includes(:producto).each do |e|
          c.lineas.create!(producto: e.producto, sistema: e.cantidad)
        end
      end
      c
    end
  end

  # ¿Toca contar? Cuando la sucursal cuenta cada N días y el último cerrado es más viejo (o no hay).
  def self.vencido?(sucursal)
    return false unless sucursal.dias_conteo
    ultimo = cerrados.where(sucursal: sucursal).maximum(:cerrado_en)
    ultimo.nil? || ultimo < sucursal.dias_conteo.days.ago
  end

  def linea_de(producto)
    if parcial?
      lineas.find_by(producto: producto) or raise ArgumentError, I18n.t("errores.conteo.fuera_de_alcance", producto: producto.nombre)
    else
      lineas.find_or_create_by!(producto: producto) { |l| l.sistema = Existencia.de(sucursal, producto) }
    end
  end

  # Escanear un producto por pieza suma una; lo que se vende en fracciones se teclea.
  def escanear!(producto)
    raise ArgumentError, I18n.t("errores.conteo.cerrado") unless abierto?
    raise ArgumentError, I18n.t("errores.conteo.se_teclea", producto: producto.nombre) if producto.fraccionable?
    linea_de(producto).increment!(:escaneado, 1)
  end

  # Lo tecleado sustituye el valor anterior, no lo suma.
  def contar_manual!(producto, cantidad)
    raise ArgumentError, I18n.t("errores.conteo.cerrado") unless abierto?
    cantidad = BigDecimal(cantidad.to_s).round(3)
    raise ArgumentError, I18n.t("errores.conteo.cantidad_invalida") if cantidad.negative?
    linea_de(producto).update!(manual: cantidad)
  end

  def cerrar!(usuario:)
    raise ArgumentError, I18n.t("errores.conteo.ya_cerrado") unless abierto?
    faltante = 0
    sobrante = 0
    detalle = []
    transaction do
      lineas.includes(:producto).each do |l|
        sistema = Existencia.de(sucursal, l.producto)
        contado = l.escaneado + l.manual
        diferencia = contado - sistema
        centavos = Dinero.importe(diferencia.abs, l.producto.precio_centavos_en(sucursal))
        l.update!(sistema: sistema, diferencia: diferencia, diferencia_centavos: diferencia.negative? ? -centavos : centavos)
        next if diferencia.zero?
        Inventario.mover!(sucursal: sucursal, producto: l.producto, tipo: diferencia.negative? ? "ajuste_salida" : "ajuste_entrada",
                          cantidad: diferencia.abs, usuario: usuario, referencia: self, motivo: "Conteo #{folio}")
        if diferencia.negative?
          faltante += centavos
          detalle << "#{l.producto.nombre}: faltan #{diferencia.abs.to_s('F')} #{l.producto.unidad} (#{Dinero.pesos(centavos)})"
        else
          sobrante += centavos
        end
      end
      update!(estado: "cerrado", cerrado_en: Time.current, faltante_centavos: faltante, sobrante_centavos: sobrante)
      cargos.create!(usuario: responsable, sucursal: sucursal, monto_centavos: faltante, detalle: detalle.join("\n")) if faltante.positive?
    end
    self
  end

  def to_s
    folio
  end

  private

  def asignar_folio
    self.folio ||= Folio.siguiente!(sucursal, "conteo") if sucursal
  end
end
