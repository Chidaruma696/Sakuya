module Admin
  class RolesController < BaseController
    before_action { autorizar!("admin.usuarios") }
    before_action :cargar, only: %i[edit update]

    def index
      @roles = Rol.order(:nombre).includes(:usuarios)
    end

    def new
      @rol = Rol.new(permisos: [])
    end

    def create
      @rol = Rol.new(permitidos)
      guardar(@rol, admin_roles_path, t("admin.avisos.creado", que: t("admin.modelos.rol")))
    end

    def edit
    end

    def update
      @rol.assign_attributes(permitidos)
      guardar(@rol, admin_roles_path, t("admin.avisos.guardado", que: t("admin.modelos.rol")))
    end

    private

    def cargar
      @rol = Rol.find(params[:id])
    end

    def permitidos
      p = params.require(:rol).permit(:nombre, permisos: [])
      p[:permisos] = Array(p[:permisos]).reject(&:blank?)
      p
    end
  end
end
