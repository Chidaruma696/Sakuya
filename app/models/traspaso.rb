# Traspaso: mercancía que cambia de sucursal. Sale del origen y entra al destino en la misma
# transacción, con folio TG por sucursal de origen. De un almacén la mercancía solo va a la
# matriz: ahí se concentra y de ahí sale.
# TODO: esa regla es del negocio, no del sistema; que la decida una regla Lisp.
class Traspaso < ApplicationRecord
  class Error < ArgumentError; end

  belongs_to :sucursal_origen, class_name: "Sucursal"
  belongs_to :sucursal_destino, class_name: "Sucursal"
  belongs_to :usuario
  has_many :lineas, class_name: "TraspasoLinea", dependent: :destroy, inverse_of: :traspaso
  # Solo para que el formulario nombre sus renglones como lineas_attributes; los renglones los arma el núcleo.
  accepts_nested_attributes_for :lineas
  has_many :movimientos, as: :referencia

  before_validation :asignar_folio, on: :create
  validates :folio, presence: true, uniqueness: { scope: :sucursal_origen_id }
  validates :fecha, presence: true
  validates :estado, inclusion: { in: %w[registrado cancelado] }
  validate { errors.add(:sucursal_destino, I18n.t("errores.traspaso.mismo_lugar")) if sucursal_origen_id == sucursal_destino_id }

  scope :registrados, -> { where(estado: "registrado") }

  def registrado? = estado == "registrado"
  def cancelado? = estado == "cancelado"
  def to_s = folio

  # `clave` es la idempotencia del navegador: la misma clave devuelve el mismo traspaso.
  def self.registrar!(origen:, destino:, usuario:, lineas:, notas: nil, fecha: Date.current, clave: nil)
    transaction do
      if clave.present? && (previo = find_by(sucursal_origen: origen, clave: clave))
        return previo
      end
      raise Error, I18n.t("errores.traspaso.mismo_lugar") if origen.id == destino.id
      raise Error, I18n.t("errores.traspaso.externo_solo_a_matriz", almacen: origen.nombre) if origen.almacen? && !destino.matriz?
      limpias = lineas.map { |l| l.to_h.symbolize_keys }.reject { |l| l[:producto_id].blank? || BigDecimal(l[:cantidad].to_s.presence || "0") <= 0 }
      raise Error, I18n.t("errores.compras.sin_renglones") if limpias.empty?
      Apartado.comprobar!(origen, limpias.map { |l| [ Producto.activos.find(l[:producto_id]), BigDecimal(l[:cantidad].to_s) ] })
      traspaso = create!(sucursal_origen: origen, sucursal_destino: destino, usuario: usuario, notas: notas.presence, fecha: fecha, clave: clave.presence)
      limpias.each do |l|
        producto = Producto.activos.find(l[:producto_id])
        linea = traspaso.lineas.create!(producto: producto, cantidad: l[:cantidad], cajas: l[:cajas].to_i)
        motivo = I18n.t("traspasos.avisos.motivo", folio: traspaso.folio, origen: origen.nombre, destino: destino.nombre)
        Inventario.mover!(sucursal: origen, producto: producto, tipo: "salida", cantidad: linea.cantidad, usuario: usuario, referencia: traspaso, motivo: motivo, fecha: fecha)
        Inventario.mover!(sucursal: destino, producto: producto, tipo: "entrada", cantidad: linea.cantidad, usuario: usuario, referencia: traspaso, motivo: motivo, fecha: fecha)
      end
      traspaso
    end
  end

  # Cancelar regresa la mercancía (si el destino todavía la tiene).
  def cancelar!(motivo:, usuario:)
    raise Error, I18n.t("errores.hace_falta_motivo") if motivo.blank?
    raise Error, I18n.t("errores.traspaso.ya_cancelado") unless registrado?
    transaction do
      motivo_kardex = I18n.t("traspasos.avisos.cancelacion", folio: folio, motivo: motivo)
      lineas.includes(:producto).each do |l|
        Inventario.mover!(sucursal: sucursal_destino, producto: l.producto, tipo: "ajuste_salida", cantidad: l.cantidad, usuario: usuario, referencia: self, motivo: motivo_kardex)
        Inventario.mover!(sucursal: sucursal_origen, producto: l.producto, tipo: "ajuste_entrada", cantidad: l.cantidad, usuario: usuario, referencia: self, motivo: motivo_kardex)
      end
      update!(estado: "cancelado", motivo_cancelacion: motivo)
    end
    self
  end

  private

  def asignar_folio
    self.folio ||= Folio.siguiente!(sucursal_origen, "traspaso") if sucursal_origen
  end
end
