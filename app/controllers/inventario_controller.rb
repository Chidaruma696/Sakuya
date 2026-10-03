class InventarioController < ApplicationController
  pestana :inventario

  before_action(except: :buscar) { autorizar!("inventario.ver") }
  before_action :cargar_sucursal, except: :buscar

  # Lo que se escaneó o tecleó: código del proveedor, PLU, clave o nombre (JSON, para los
  # formularios de renglones: recepción, factura, traspaso a granel).
  def buscar
    q = params[:q].to_s.strip
    escaneado = Escaneo.resolver(q)
    productos = if escaneado&.producto && escaneado.producto.activo
      [ escaneado.producto ]
    else
      Producto.activos.where("LOWER(nombre) LIKE :q OR LOWER(clave) LIKE :q", q: "%#{q.downcase}%").order(:nombre).limit(10)
    end
    render json: productos.map { |p| { id: p.id, nombre: p.nombre, unidad: p.unidad } }
  end

  def index
    @existencias = Existencia.where(sucursal: @sucursal).includes(:producto)
                             .joins(:producto).order("productos.nombre")
  end

  def kardex
    @producto = Producto.find_by(id: params[:producto_id])
    @movimientos = Movimiento.where(sucursal: @sucursal).includes(:producto, :usuario)
                             .order(created_at: :desc).limit(200)
    @movimientos = @movimientos.where(producto: @producto) if @producto
  end

  def nuevo_movimiento
    @movimiento = Movimiento.new(tipo: "entrada")
  end

  # El movimiento lo juzga la regla de movimientos (ReglaMovimiento): lo que frena no se mueve y
  # queda reportado, salvo que lo haga alguien con inventario.ajustar (entonces queda por revisar).
  def crear_movimiento
    return volver_con_error(t("errores.escribe_motivo")) if params[:motivo].blank?
    producto = Producto.activos.find(params[:producto_id])
    tipo = params[:tipo].presence_in(ReglaMovimiento::TIPOS.keys) || "entrada"
    decision = ReglaMovimiento.decidir(sucursal: @sucursal, producto: producto, tipo: tipo, cantidad: params[:cantidad], motivo: params[:motivo], usuario: usuario_actual)
    fallo = (t("regla_movimiento.fallo", error: decision.error) if decision.error)
    con_permiso = puede?("inventario.ajustar")
    if decision.rechaza? && !con_permiso
      reporte = [ t("inventario.movimiento_frenado", tipo: t("movimientos.#{tipo}"), cantidad: params[:cantidad], motivo: params[:motivo], regla: decision.motivo), fallo ].compact.join("\n")
      Revision.abrir!(producto, usuario: usuario_actual, sucursal: @sucursal, motivo: reporte, frenado: true,
                      valor_centavos: Revision.valor(BigDecimal(params[:cantidad].to_s), producto, @sucursal))
      return volver_con_error(t("errores.inventario.movimiento_frenado", motivo: decision.motivo))
    end
    revisar = decision.permite? && !fallo ? nil : [ params[:motivo], (decision.motivo unless decision.permite?), fallo ].compact.join("\n")
    nota = if revisar then " (#{t("comun.por_revisar")})" elsif con_permiso then " (#{t("comun.autorizo")} #{usuario_actual.nombre})" end
    movimiento = Inventario.mover!(sucursal: @sucursal, producto: producto, tipo: tipo, cantidad: params[:cantidad], usuario: usuario_actual,
                                   motivo: "#{params[:motivo]}#{nota}")
    if revisar
      Revision.abrir!(movimiento, usuario: usuario_actual, sucursal: @sucursal, motivo: revisar, valor_centavos: Revision.valor(movimiento.cantidad, producto, @sucursal))
    end
    redirect_to kardex_inventario_path(producto_id: producto.id, sucursal_id: @sucursal.id),
                notice: "#{I18n.t("movimientos.#{tipo}")} de #{producto.nombre} registrada#{'; queda por revisar' if revisar}"
  rescue Inventario::SinExistencia, ArgumentError => e
    volver_con_error(e.message)
  end

  private

  # La matriz puede mirar cualquier sucursal; una tienda solo la suya.
  def cargar_sucursal
    @sucursal = sucursal_actual
    if params[:sucursal_id].present? && (sucursal_actual.matriz? || puede?("admin.usuarios"))
      @sucursal = Sucursal.find(params[:sucursal_id])
    end
  end

  def volver_con_error(mensaje)
    @movimiento = Movimiento.new(tipo: params[:tipo], producto_id: params[:producto_id], cantidad: params[:cantidad], motivo: params[:motivo])
    flash.now[:alert] = mensaje
    render :nuevo_movimiento, status: :unprocessable_entity
  end
end
