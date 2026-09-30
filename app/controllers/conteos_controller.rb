class ConteosController < ApplicationController
  pestana :conteos
  modulo :conteos

  before_action { autorizar!("conteos.hacer") }
  before_action :cargar_conteo, only: %i[show escanear manual cerrar]

  def index
    @conteos = Conteo.where(sucursal: sucursal_actual).includes(:usuario, :responsable, :lineas).order(created_at: :desc).limit(30)
    @vencido = Conteo.vencido?(sucursal_actual)
  end

  def new
    @abierto = Conteo.abiertos.find_by(sucursal: sucursal_actual)
    @responsables = Usuario.activos.where(sucursal: sucursal_actual).order(:nombre)
    @lineas = Producto.activos.where.not(linea: [ nil, "" ]).distinct.order(:linea).pluck(:linea)
    @productos = Producto.activos.order(:nombre)
  end

  # Todo, o solo una línea o unos productos (parcial): lo demás no se toca al cerrar.
  def create
    productos = if params[:alcance] == "parcial"
      params[:linea].present? ? Producto.activos.where(linea: params[:linea]).order(:nombre).to_a : Producto.activos.where(id: params[:producto_ids]).order(:nombre).to_a
    end
    conteo = Conteo.abrir!(sucursal: sucursal_actual, usuario: usuario_actual, responsable: Usuario.activos.find(params[:responsable_id]), productos: productos)
    redirect_to conteo_path(conteo), notice: t("conteos.avisos.abierto", folio: conteo.folio)
  rescue ArgumentError => e
    redirect_to new_conteo_path, alert: e.message
  end

  def show
    @lineas = @conteo.lineas.includes(:producto).joins(:producto).order("productos.nombre")
    @productos = @conteo.parcial? ? @lineas.map(&:producto) : Producto.activos.order(:nombre)
  end

  def escanear
    producto = Escaneo.resolver(params[:codigo])&.producto or raise ArgumentError, t("errores.conteo.no_encontrado", codigo: params[:codigo])
    @conteo.escanear!(producto)
    redirect_to conteo_path(@conteo), notice: t("conteos.avisos.contado", producto: producto.nombre)
  rescue ArgumentError => e
    redirect_to conteo_path(@conteo), alert: e.message
  end

  def manual
    producto = Producto.activos.find(params[:producto_id])
    @conteo.contar_manual!(producto, params[:cantidad])
    redirect_to conteo_path(@conteo), notice: "#{producto.nombre}: #{params[:cantidad]} contado a mano"
  rescue ArgumentError => e
    redirect_to conteo_path(@conteo), alert: e.message
  end

  def cerrar
    @conteo.cerrar!(usuario: usuario_actual)
    aviso = "Conteo #{@conteo.folio} cerrado: faltante #{Dinero.pesos(@conteo.faltante_centavos)}, sobrante #{Dinero.pesos(@conteo.sobrante_centavos)}"
    aviso += " · cargo a #{@conteo.responsable}" if @conteo.faltante_centavos.positive?
    redirect_to conteo_path(@conteo), notice: aviso
  rescue ArgumentError, Inventario::SinExistencia => e
    redirect_to conteo_path(@conteo), alert: e.message
  end

  private

  def cargar_conteo
    @conteo = Conteo.where(sucursal: sucursal_actual).find(params[:id])
  end
end
