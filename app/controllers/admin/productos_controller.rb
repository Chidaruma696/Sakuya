module Admin
  class ProductosController < BaseController
    before_action { autorizar!("admin.catalogo") }
    before_action :cargar, only: %i[edit update]

    def index
      @productos = Producto.order(:nombre).includes(:codigos_barras)
      @productos = @productos.where("nombre LIKE :q OR clave LIKE :q", q: "%#{params[:q]}%") if params[:q].present?
    end

    def new
      @producto = Producto.new(unidad: "kg")
    end

    def create
      @producto = Producto.new(permitidos)
      guardar(@producto, -> { edit_admin_producto_path(@producto) }, t("admin.avisos.creado", que: t("admin.modelos.producto")))
    end

    def edit
    end

    def update
      @producto.assign_attributes(permitidos)
      Producto.transaction do
        params.fetch(:precios, {}).each { |sucursal_id, pesos| @producto.fijar_precio!(Sucursal.find(sucursal_id), pesos) } if @producto.valid?
        guardar(@producto, admin_productos_path, t("admin.avisos.guardado", que: t("admin.modelos.producto")))
      end
    end

    private

    def cargar
      @producto = Producto.find(params[:id])
    end

    def permitidos
      p = params.require(:producto).permit(:clave, :nombre, :linea, :unidad, :precio, :plu, :activo)
      p[:clave] = p[:clave].to_s.strip.upcase if p.key?(:clave)
      p[:plu] = nil if p.key?(:plu) && p[:plu].blank?
      p
    end
  end
end
