# Clientes: alta y edición. Su cuenta y sus pedidos viven aparte.
class ClientesController < ApplicationController
  pestana :clientes
  modulo :clientes

  before_action { autorizar!("clientes.ver") }
  before_action(only: %i[new create edit update]) { autorizar!("clientes.editar") }

  def index
    @clientes = Cliente.order(:nombre).to_a.sort_by { |c| [ c.activo ? 0 : 1, c.nombre.downcase ] }
    @clientes = @clientes.select { |c| c.nombre.downcase.include?(params[:q].to_s.downcase.strip) } if params[:q].present?
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
