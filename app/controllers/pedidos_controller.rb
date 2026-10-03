# Pedidos de clientes: se toman aquí y se cobran en la caja («Cobrar en caja» arma el ticket).
class PedidosController < ApplicationController
  pestana :clientes
  modulo :clientes

  before_action { autorizar!("clientes.ver") }
  before_action(only: %i[new create cancelar]) { autorizar!("clientes.pedidos") }

  def index
    @estado = params[:estado].presence_in(Pedido::ESTADOS) || "abierto"
    @pedidos = Pedido.where(sucursal: sucursal_actual, estado: @estado).includes(:cliente, :usuario, lineas: :producto)
                     .order(Arel.sql("fecha_entrega IS NULL"), :fecha_entrega, :id).limit(200)
  end

  def new
    @pedido = Pedido.new(cliente_id: params[:cliente_id])
    @pedido.lineas.build
    cargar_listas
  end

  def create
    @pedido = Pedido.new(params.require(:pedido).permit(:cliente_id, :fecha_entrega, :notas, lineas_attributes: %i[producto_id cantidad]))
    @pedido.assign_attributes(sucursal: sucursal_actual, usuario: usuario_actual)
    @pedido.cliente = Cliente.activos.find_by(id: @pedido.cliente_id)
    if @pedido.save
      redirect_to pedido_path(@pedido), notice: t("pedidos.avisos.creado", folio: @pedido.folio, cliente: @pedido.cliente)
    else
      @pedido.lineas.build if @pedido.lineas.empty?
      cargar_listas
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @pedido = Pedido.where(sucursal: sucursal_actual).includes(:cliente, :venta, lineas: :producto).find(params[:id])
  end

  def cancelar
    pedido = Pedido.where(sucursal: sucursal_actual).find(params[:id])
    pedido.cancelar!(motivo: params[:motivo].to_s.strip)
    redirect_to pedido_path(pedido), notice: t("pedidos.avisos.cancelado", folio: pedido.folio)
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to pedido_path(pedido), alert: e.message
  end

  private

  def cargar_listas
    @clientes = Cliente.activos.order(:nombre)
    @productos = Producto.activos.order(:nombre)
  end
end
