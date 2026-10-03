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

  scope :active, -> { where(active: true) }

  def can?(key)
    active && role.allows?(key)
  end


  def to_s
    name
  end
end
