# Proveedores: alta y edición. Lo que se les debe vive en Cuentas.
class ProveedoresController < ApplicationController
  pestana :compras
  modulo :compras

  before_action { autorizar!("compras.ver") }
  before_action(only: %i[new create edit update]) { autorizar!("compras.facturar") }

  def index
    @proveedores = Proveedor.order(:activo, :nombre).reverse_order.includes(:movimientos).to_a.sort_by { |p| [ p.activo ? 0 : 1, p.nombre.downcase ] }
    @saldos = MovimientoProveedor.group(:proveedor_id).sum(:delta_centavos)
  end

  def new
    @proveedor = Proveedor.new
  end

  def create
    @proveedor = Proveedor.new(datos)
    if @proveedor.save
      redirect_to proveedores_path, notice: t("compras.avisos.proveedor_creado", nombre: @proveedor.nombre)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @proveedor = Proveedor.find(params[:id])
  end

  def update
    @proveedor = Proveedor.find(params[:id])
    if @proveedor.update(datos)
      redirect_to proveedores_path, notice: t("compras.avisos.proveedor_guardado", nombre: @proveedor.nombre)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def datos
    params.require(:proveedor).permit(:nombre, :rfc, :contacto, :telefono, :dias_credito, :notas, :activo)
  end
end
