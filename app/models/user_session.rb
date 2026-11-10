# One device signed in as one user. The cookie holds the token; only its digest is stored, so
# reading this table gives nobody a session. A user holds as many as their limit: signing in
# beyond it ends the oldest. A session nobody uses ends by itself.
class UserSession < ApplicationRecord
  IDLE_AFTER = 15.minutes # without anyone touching the screen, it asks "are you still there?"
  COUNTDOWN = 60.seconds  # and after this long without an answer, it closes
  # What the server allows on top: the screen tells it about activity at most once a minute, so
  # its clock runs behind the screen's. Whoever answers in time is never turned away.
  GRACE = 2.minutes
  RECORD_EVERY = 10.seconds # how often `last_used_at` is written while someone works

  belongs_to :user

  # Starts a session and ends whatever that user holds beyond their limit, oldest first.
  # Returns the session and its token (which is not stored anywhere).
  def self.start!(user, user_agent: nil)
    token = SecureRandom.urlsafe_base64(32)
    transaction do
      session = create!(user: user, token_digest: digest(token), started_at: Time.current, last_used_at: Time.current, device: device(user_agent))
      trim!(user)
      [ session, token ]
    end
  end

  # Ends the sessions a user holds beyond their limit, oldest first.
  def self.trim!(user)
    surplus = where(user: user).order(started_at: :desc, id: :desc).pluck(:id).drop(user.session_limit)
    where(id: surplus).delete_all if surplus.any?
  end

  # The session that cookie belongs to, if it exists and the token is its own.
  def self.find_live(id, token)
    session = find_by(id: id) if id.to_s.match?(/\A\d+\z/)
    session if session && ActiveSupport::SecurityUtils.secure_compare(session.token_digest, digest(token.to_s))
  end

  def self.digest(token) = Digest::SHA256.hexdigest(token)

  # "Chrome · Windows": enough to tell one's own devices apart. The raw User-Agent is not kept.
  def self.device(user_agent)
    agent = user_agent.to_s
    browser = { "Edg" => "Edge", "OPR" => "Opera", "Firefox" => "Firefox", "Chrome" => "Chrome", "Safari" => "Safari" }.find { |mark, _| agent.include?("#{mark}/") }&.last
    system = { "Windows" => "Windows", "Android" => "Android", "iPhone" => "iPhone", "iPad" => "iPad", "Mac OS X" => "Mac", "CrOS" => "ChromeOS", "Linux" => "Linux" }.find { |mark, _| agent.include?(mark) }&.last
    [ browser, system ].compact.join(" · ").presence
  end

  def idle? = last_used_at < (IDLE_AFTER + COUNTDOWN + GRACE).ago

  # Someone did something on this device.
  def use!
    update_column(:last_used_at, Time.current) if last_used_at < RECORD_EVERY.ago
  end
end
