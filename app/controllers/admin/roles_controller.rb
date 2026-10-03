module Admin
  class RolesController < BaseController
    before_action { authorize!("admin.users") }
    before_action :load_record, only: %i[edit update]

    def index
      @roles = Role.order(:name).includes(:users)
    end

    def new
      @role = Role.new(permissions: [])
    end

    def create
      @role = Role.new(allowed)
      save(@role, admin_roles_path, t("admin.notices.created", what: t("admin.models.role")))
    end

    def edit
    end

    def update
      @role.assign_attributes(allowed)
      save(@role, admin_roles_path, t("admin.notices.saved", what: t("admin.models.role")))
    end

    private

    def load_record
      @role = Role.find(params[:id])
    end

    def allowed
      p = params.require(:role).permit(:name, permissions: [])
      p[:permissions] = Array(p[:permissions]).reject(&:blank?)
      p
    end
  end
end
