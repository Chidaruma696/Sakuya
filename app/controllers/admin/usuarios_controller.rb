module Admin
  class UsuariosController < BaseController
    before_action { autorizar!("admin.usuarios") }
    before_action :cargar, only: %i[edit update]

    def index
      @usuarios = Usuario.includes(:rol, :sucursal).order(:nombre)
    end

    def new
      @usuario = Usuario.new(sucursal: sucursal_actual, activo: true)
    end

    def create
      @usuario = Usuario.new(permitidos)
      guardar(@usuario, admin_usuarios_path, t("admin.avisos.creado", que: t("admin.modelos.usuario")))
    end

    def edit
    end

    def update
      @usuario.assign_attributes(permitidos)
      guardar(@usuario, admin_usuarios_path, t("admin.avisos.guardado", que: t("admin.modelos.usuario")))
    end

    private

    def cargar
      @usuario = Usuario.find(params[:id])
    end

    # La contraseña solo cambia si se escribe.
    def permitidos
      p = params.require(:usuario).permit(:nombre, :usuario, :rol_id, :sucursal_id, :activo, :password)
      p[:usuario] = p[:usuario].to_s.strip.downcase
      p.delete(:password) if p[:password].blank?
      p
    end
  end
end
