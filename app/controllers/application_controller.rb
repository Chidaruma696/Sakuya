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
    Current.user ||= User.active.includes(:role, :branch).find_by(id: cookies.signed[:user_id])
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

  def require_session
    redirect_to login_path, alert: t("session.sign_in_to_continue") unless current_user
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

  def start_session(user)
    cookies.signed.permanent[:user_id] = { value: user.id, httponly: true, same_site: :lax }
    Current.user = user
  end

  def close_session
    cookies.delete(:user_id)
    Current.reset
  end
end
