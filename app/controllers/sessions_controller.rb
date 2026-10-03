class SessionsController < ApplicationController
  skip_before_action :require_session, only: %i[new create]
  layout "session"

  def new
    redirect_to root_path if current_user
  end

  def create
    user = User.active.find_by(user: params[:user].to_s.strip.downcase)
    if user&.authenticate(params[:password])
      start_session(user)
      redirect_to root_path, notice: I18n.t("session.welcome", name: user.name, locale: user.language)
    else
      flash.now[:alert] = t("session.wrong")
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    close_session
    redirect_to login_path, notice: t("session.closed")
  end
end
