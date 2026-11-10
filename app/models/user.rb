class User < ApplicationRecord
  belongs_to :role
  belongs_to :branch

  has_secure_password

  LANGUAGES = %w[es en de].freeze
  THEMES = %w[system light dark].freeze
  DENSITIES = %w[normal compact].freeze
  TEXT_SIZES = %w[small normal large].freeze

  validates :name, presence: true
  validates :language, inclusion: { in: ->(_) { Languages.all } }
  validates :theme, inclusion: { in: THEMES }
  validates :density, inclusion: { in: DENSITIES }
  validates :text_size, inclusion: { in: TEXT_SIZES }
  validates :user, presence: true, uniqueness: true,
                      format: { with: /\A[a-z0-9._-]+\z/, message: ->(*) { I18n.t("errors.user.format") } }

  has_many :charges, dependent: :restrict_with_error

  validate :someone_still_manages_users, on: :update

  scope :active, -> { where(active: true) }

  # What a session cookie must match to stay valid: it changes with the password.
  def session_stamp = Digest::SHA256.hexdigest("#{id}:#{password_digest}")[0, 32]

  def can?(key)
    active && role.allows?(key)
  end


  def to_s
    name
  end

  private

  # Nobody locks the business out: the last active user who can manage users cannot be switched
  # off or moved to a role without that permission. (With no active user at all, the first-run
  # setup would open again for whoever got there first.)
  def someone_still_manages_users
    return unless active_changed? || role_id_changed?
    return if active && role&.allows?("admin.users")
    return unless active_was && Role.find_by(id: role_id_was)&.allows?("admin.users")
    others = User.active.where.not(id: id).includes(:role).any? { |u| u.role.allows?("admin.users") }
    errors.add(:base, I18n.t("errors.user.last_admin")) unless others
  end
end
