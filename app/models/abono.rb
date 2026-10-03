# Dinero que un cliente paga a su cuenta. Entra a la caja abierta al momento (si es en efectivo,
# a la gaveta) y queda en su cuenta como abono. Solo inserción.
class Abono < ApplicationRecord
  belongs_to :cliente
  belongs_to :sucursal
  belongs_to :corte
  belongs_to :usuario

  before_validation :asignar_folio, on: :create

  validates :folio, presence: true, uniqueness: { scope: :sucursal_id }
  validates :monto_centavos, numericality: { only_integer: true, greater_than: 0 }
  validates :forma, inclusion: { in: Pago::FORMAS }

  before_update { raise ActiveRecord::ReadOnlyRecord, "los abonos no se editan" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "los abonos no se borran" }

  def self.registrar!(cliente:, sucursal:, usuario:, monto_centavos:, forma:, notas: nil)
    raise ArgumentError, I18n.t("errores.abono.mayor_que_cero") unless monto_centavos.to_i.positive?
    corte = Corte.abierto_en(sucursal) or raise ArgumentError, I18n.t("errores.abono.sin_caja", sucursal: sucursal.nombre)
    transaction do
      abono = create!(cliente: cliente, sucursal: sucursal, corte: corte, usuario: usuario, monto_centavos: monto_centavos.to_i, forma: forma, notas: notas.presence)
      cliente.movimientos_credito.create!(tipo: "abono", monto_centavos: -abono.monto_centavos, fecha: Date.current, referencia: abono,
                                          sucursal: sucursal, usuario: usuario, motivo: I18n.t("clientes.cuenta.abono", folio: abono.folio, forma: I18n.t("formas_pago.#{forma}")))
      abono
    end
  end

  def to_s = folio

  private

  def asignar_folio
    self.folio ||= Folio.siguiente!(sucursal, "abono") if sucursal
  end
end
