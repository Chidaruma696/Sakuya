module Admin
  class UsersController < BaseController
    before_action { authorize!("admin.users") }
    before_action :load_record, only: %i[edit update]

    def index
      @users = User.includes(:role, :branch).order(:name)
    end

    def new
      @user = User.new(branch: current_branch, active: true)
    end

    def create
      @user = User.new(allowed)
      save(@user, admin_users_path, t("admin.notices.created", what: t("admin.models.user")))
    end

    def edit
    end

    def update
      @user.assign_attributes(allowed)
      save(@user, admin_users_path, t("admin.notices.saved", what: t("admin.models.user")))
    end

    private

    def load_record
      @user = User.find(params[:id])
    end

    # The password only changes if one is typed.
    def allowed
      p = params.require(:user).permit(:name, :user, :role_id, :branch_id, :active, :password)
      p[:user] = p[:user].to_s.strip.downcase
      p.delete(:password) if p[:password].blank?
      p
    end
  end
end
