module Admin
  class SucursalesController < BaseController
    before_action { autorizar!("admin.usuarios") }
    before_action :cargar, only: %i[edit update]

    def index
      @sucursales = Sucursal.order(:nombre)
    end

    def new
      @sucursal = Sucursal.new(tipo: "tienda", activa: true)
    end

    def create
      @sucursal = Sucursal.new(permitidos)
      guardar(@sucursal, admin_sucursales_path, t("admin.avisos.creado", que: t("admin.modelos.sucursal")))
    end

    def edit
    end

    def update
      @sucursal.assign_attributes(permitidos)
      guardar(@sucursal, admin_sucursales_path, t("admin.avisos.guardado", que: t("admin.modelos.sucursal")))
    end

    private

    def cargar
      @sucursal = Sucursal.find(params[:id])
    end

    def permitidos
      p = params.require(:sucursal).permit(:codigo, :nombre, :tipo, :activa, :limite_efectivo, :dias_conteo)
      p[:codigo] = p[:codigo].to_s.strip.upcase
      p[:limite_efectivo_centavos] = Dinero.centavos(p.delete(:limite_efectivo)) if p.key?(:limite_efectivo)
      p
    end
  end
end
