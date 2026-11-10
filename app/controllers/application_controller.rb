class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  class NotAllowed < StandardError; end

  # Ribbon tab this controller belongs to (see RibbonHelper).
  class_attribute :ribbon_tab, default: :home
  def self.tab(id) = self.ribbon_tab = id

  # Optional features this controller depends on (see Features); empty = always available.
  class_attribute :required_features, default: []
  def self.feature(*keys) = self.required_features = keys.map(&:to_s)

  before_action :require_setup, :require_session, :require_feature
  around_action :with_language
  helper_method :current_user, :current_branch, :can?

  # An amount nobody can read ("abc", "12,50") typed anywhere: back to where it came from, with the reason.
  rescue_from Money::Invalid do |e|
    redirect_back_or_to root_path, alert: e.message
  end

  # The database refused a duplicate: the same form sent twice at the same instant, or the same
  # thing done from two screens. Nothing was recorded twice; say so.
  rescue_from ActiveRecord::RecordNotUnique do
    respond_to do |format|
      format.json { render json: { error: t("errors.duplicate") }, status: :conflict }
      format.any { redirect_back_or_to root_path, alert: t("errors.duplicate") }
    end
  end

  rescue_from NotAllowed do |e|
    render "errors/not_allowed", status: :forbidden, locals: { key: e.message }
  end

  private

  # Everyone sees the system in their own language; without a session, the one requested (?language=,
  # remembered in a cookie) or the browser's if we have it.
  def with_language(&)
    Languages.sync!
    languages = I18n.available_locales.map(&:to_s)
    cookies[:language] = params[:language] if params[:language].presence_in(languages)
    # A language from a plugin that has been turned off falls back to the default.
    language = current_user&.language.presence_in(languages) || cookies[:language].presence_in(languages) || http_accept_language_preferred
    I18n.with_locale(language, &)
  end

  def http_accept_language_preferred
    request.env["HTTP_ACCEPT_LANGUAGE"].to_s.scan(/[a-z]{2}/).find { |l| I18n.available_locales.map(&:to_s).include?(l) } || I18n.default_locale
  end

  def current_user
    Current.user ||= user_from_cookie
  end

  def current_branch
    Current.branch ||= current_user&.branch
  end

  # With no active user the system is freshly installed (or nobody can sign in):
  # the administrator is created first.
  def require_setup
    redirect_to install_path if User.active.none?
  end

  # A feature that is turned off does not exist: its screens say so instead of a bare 404.
  def require_feature
    off = required_features.find { |m| !Features.active?(m) } or return
    render "errors/feature_off", status: :not_found, locals: { feature: off }
  end

  # Without a session: to the sign-in screen, saying why if this device had one and lost it.
  # What the page asks for by itself (JSON) gets a 401 it can read instead of a login page.
  def require_session
    return if current_user
    message = case @session_ended
    when :idle then t("session.closed_idle", minutes: UserSession::IDLE_AFTER.in_minutes.to_i)
    when :elsewhere then t("session.opened_elsewhere")
    else t("session.sign_in_to_continue")
    end
    if request.format.json? || request.headers["Accept"].to_s.include?("application/json")
      render json: { error: message, signed_out: true }, status: :unauthorized
    else
      redirect_to login_path, alert: message
    end
  end

  def can?(key)
    current_user&.can?(key) || false
  end

  # Stops the request if the user lacks the permission.
  def authorize!(key)
    raise NotAllowed, key unless can?(key)
  end

  # Deferred authorization (there is no PIN): if the operator has the permission, it goes on record
  # under their name; if not, the operation goes ahead anyway and is left for review (see Review).
  # Returns the authorizer or nil.
  def authorizer_or_review(key)
    can?(key) ? current_user : nil
  end

  # Puts the operation in the review inbox if nobody authorized it.
  def review_if_needed(record, authorizes, reason:, value_cents: 0, branch: current_branch)
    return if authorizes
    Review.open!(record, user: current_user, branch: branch, reason: reason, value_cents: value_cents)
  end

  # Signing in starts a session of this user on this device (see UserSession: beyond the user's
  # limit, their oldest one ends). The cookie carries the session, its token and the user.
  def start_session(user)
    session, token = UserSession.start!(user, user_agent: request.user_agent)
    cookies.signed[:user_id] = { value: "#{session.id}:#{token}:#{user.id}", expires: 1.day, httponly: true, same_site: :lax }
    Current.session = session
    Current.user = user
  end

  # Who this device is signed in as, if its session is still alive. A device whose session ended
  # (left unused, or ended from somewhere else) is remembered for this request, to tell it why.
  def user_from_cookie
    session_id, token, user_id = cookies.signed[:user_id].to_s.split(":", 3)
    return if token.blank?
    session = UserSession.find_live(session_id, token)
    user = User.active.includes(:role, :branch).find_by(id: session.user_id) if session && !session.idle?
    unless user
      @session_ended = session&.idle? ? :idle : (:elsewhere if user_id.present?)
      session&.destroy
      cookies.delete(:user_id)
      return
    end
    # What the page does by itself (the till looking for sales to upload) is not someone using it.
    session.use! if request.headers["X-Background"].blank?
    Current.session = session
    user
  end

  # Ends this device's session for real: the row goes, so no copy of the cookie works afterwards.
  def close_session
    current_user
    Current.session&.destroy
    cookies.delete(:user_id)
    Current.reset
  end
end
