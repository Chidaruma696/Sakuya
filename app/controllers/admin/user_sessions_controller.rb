module Admin
  # Ending someone's session from the user list: that device is signed out on its next request.
  class UserSessionsController < BaseController
    before_action { authorize!("admin.users") }

    def destroy
      session = UserSession.where(user_id: params[:user_id]).find(params[:id])
      session.destroy
      redirect_to admin_users_path, notice: t("admin.notices.session_ended", name: session.user.name)
    end
  end
end
