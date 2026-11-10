class SessionsController < ApplicationController
  skip_before_action :require_session, only: %i[new create]
  layout "session"

  def new
    redirect_to root_path if current_user
  end

  # Wrong passwords, per user name and address; a right one clears the count.
  ATTEMPTS = ActiveSupport::Cache::MemoryStore.new
  MAX_ATTEMPTS = 8
  LOCKED_FOR = 5.minutes

  def create
    name = params[:user].to_s.strip.downcase
    attempts = "login:#{request.remote_ip}:#{name.first(40)}"
    if ATTEMPTS.read(attempts).to_i >= MAX_ATTEMPTS
      flash.now[:alert] = t("session.too_many")
      return render :new, status: :too_many_requests
    end
    user = User.active.find_by(user: name)
    if user&.authenticate(params[:password])
      ATTEMPTS.delete(attempts)
      start_session(user)
      redirect_to root_path, notice: I18n.t("session.welcome", name: user.name, locale: user.language)
    else
      ATTEMPTS.write(attempts, ATTEMPTS.read(attempts).to_i + 1, expires_in: LOCKED_FOR)
      flash.now[:alert] = t("session.wrong")
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    close_session
    redirect_to login_path, notice: t("session.closed")
  end
end
