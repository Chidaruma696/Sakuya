# Autorización diferida. Cuando una operación necesita a alguien con permiso y no hay nadie
# (un ajuste, un retiro, un precio abajo del catálogo), el operador la hace con su motivo y
# queda aquí a su nombre. El supervisor la revisa después: la aprueba o la observa, y si la
# observa puede cargársela al responsable. Lo irregular nunca se pierde.
class Revision < ApplicationRecord
  self.table_name = "revisiones"
  ESTADOS = %w[pendiente aprobada observada].freeze

  belongs_to :sucursal
  belongs_to :usuario
  belongs_to :revisable, polymorphic: true
  belongs_to :revisado_por, class_name: "Usuario", optional: true
  has_one :cargo, dependent: :nullify

  validates :motivo, presence: true
  validates :estado, inclusion: { in: ESTADOS }
  validates :valor_centavos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :pendientes, -> { where(estado: "pendiente") }
  scope :resueltas, -> { where.not(estado: "pendiente") }

  # frenado: la operación no pasó (una regla la frenó) y lo que se revisa es el intento; va
  # colgado del corte donde ocurrió. Un intento frenado igual a uno pendiente no se repite, ni
  # lo que se pida `sin_repetir` (el fallo de una regla, que saldría en cada venta).
  def self.abrir!(registro, usuario:, sucursal:, motivo:, valor_centavos: 0, frenado: false, sin_repetir: false)
    if (frenado || sin_repetir) && (igual = pendientes.find_by(revisable: registro, usuario: usuario, motivo: motivo, frenado: frenado))
      return igual
    end
    create!(revisable: registro, usuario: usuario, sucursal: sucursal, motivo: motivo, valor_centavos: valor_centavos.to_i, frenado: frenado)
  end

  # Lo que vale la mercancía de la operación, a precio de catálogo de la sucursal.
  def self.valor(cantidad, producto, sucursal)
    (BigDecimal(cantidad.to_s) * producto.precio_centavos_en(sucursal)).round.to_i
  end

  def pendiente? = estado == "pendiente"

  def aprobar!(usuario:, nota: nil)
    resolver!("aprobada", usuario: usuario, nota: nota)
  end

  # Observada: queda como irregular y, si se indica monto, se le carga al responsable.
  def observar!(usuario:, nota: nil, cargo_centavos: 0)
    transaction do
      resolver!("observada", usuario: usuario, nota: nota)
      if cargo_centavos.to_i.positive?
        create_cargo!(usuario: self.usuario, sucursal: sucursal, monto_centavos: cargo_centavos.to_i,
                      detalle: [ descripcion, motivo, nota ].compact_blank.join("\n"))
      end
    end
    self
  end

  # Qué fue lo que se hizo, en una línea.
  def descripcion
    return I18n.t("revisiones.desc.frenado", folio: revisable.to_s) if frenado?
    case revisable
    when Movimiento then I18n.t("revisiones.desc.movimiento", tipo: revisable.nombre_tipo, cantidad: cantidad_de(revisable))
    when Retiro then I18n.t("revisiones.desc.retiro", monto: Dinero.pesos(revisable.monto_centavos), folio: revisable.corte.folio)
    when FacturaProveedor then I18n.t("revisiones.desc.factura_proveedor", folio: revisable.folio, proveedor: revisable.proveedor.nombre)
    when Corte
      return I18n.t("revisiones.desc.corte_abierto", folio: revisable.folio) if revisable.abierto?
      I18n.t("revisiones.desc.corte", folio: revisable.folio, diferencia: Dinero.pesos(revisable.diferencia_centavos))
    when VentaLinea
      I18n.t("revisiones.desc.venta_linea", folio: revisable.venta.folio, producto: revisable.producto.nombre, precio: Dinero.pesos(revisable.precio_centavos), catalogo: Dinero.pesos(revisable.catalogo_centavos))
    else "#{revisable_type} #{revisable_id}"
    end
  end

  private

  def resolver!(nuevo_estado, usuario:, nota:)
    raise ArgumentError, I18n.t("errores.revision.ya_esta", estado: I18n.t("estados.#{estado}")) unless pendiente?
    update!(estado: nuevo_estado, revisado_por: usuario, revisado_en: Time.current, nota: nota)
  end

  def cantidad_de(registro)
    producto = registro.producto
    "#{ActiveSupport::NumberHelper.number_to_rounded(registro.cantidad, precision: producto.decimales)} #{producto.unidad} #{producto.nombre}"
  end
end
