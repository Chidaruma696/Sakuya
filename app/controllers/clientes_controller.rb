# Clientes: alta y edición. Su cuenta y sus pedidos viven aparte.
class ClientesController < ApplicationController
  pestana :clientes
  modulo :clientes

  before_action { autorizar!("clientes.ver") }
  before_action(only: %i[new create edit update]) { autorizar!("clientes.editar") }

  def index
    @clientes = Cliente.order(:nombre).to_a.sort_by { |c| [ c.activo ? 0 : 1, c.nombre.downcase ] }
    @clientes = @clientes.select { |c| c.nombre.downcase.include?(params[:q].to_s.downcase.strip) } if params[:q].present?
    @saldos = MovimientoCredito.group(:cliente_id).sum(:monto_centavos)
  end

  # Estado de cuenta: lo que debe, desde cuándo, cada movimiento con su saldo, y recibir un abono.
  def cuenta
    @cliente = Cliente.find(params[:id])
    @cuenta = @cliente.cuenta
    saldo = 0
    @movimientos = @cuenta.movimientos.map { |m| [ m, saldo += m.monto_centavos ] }.reverse.first(200)
    @corte = Corte.abierto_en(sucursal_actual)
  end

  def abonar
    autorizar!("clientes.abonar")
    cliente = Cliente.find(params[:id])
    abono = Abono.registrar!(cliente: cliente, sucursal: sucursal_actual, usuario: usuario_actual, monto_centavos: Dinero.centavos(params[:monto]),
                             forma: params[:forma].presence_in(Pago::FORMAS) || "efectivo", notas: params[:notas])
    redirect_to cuenta_cliente_path(cliente), notice: t("clientes.avisos.abono", folio: abono.folio, monto: Dinero.pesos(abono.monto_centavos), saldo: Dinero.pesos(cliente.saldo_centavos))
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to cuenta_cliente_path(cliente), alert: e.message
  end

  def new
    @cliente = Cliente.new
  end

  def create
    @cliente = Cliente.new(datos)
    if @cliente.save
      redirect_to clientes_path, notice: t("clientes.avisos.creado", nombre: @cliente.nombre)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @cliente = Cliente.find(params[:id])
  end

  def update
    @cliente = Cliente.find(params[:id])
    if @cliente.update(datos)
      redirect_to clientes_path, notice: t("clientes.avisos.guardado", nombre: @cliente.nombre)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def datos
    params.require(:cliente).permit(:nombre, :telefono, :rfc, :direccion, :notas, :limite_credito, :activo)
  end
end
