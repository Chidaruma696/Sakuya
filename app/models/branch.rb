class Branch < ApplicationRecord
  # head_office: the central office, where everything comes from. store: sells. warehouse: where
  # goods are only kept: no till and no counts; stock comes and goes by transfers, and only to the head office.
  KINDS = %w[head_office store warehouse].freeze
  # How it prints tickets: through the browser, on a network thermal printer or on a wired one (Web Serial).
  PRINTERS = %w[browser network serial].freeze

  has_many :users, dependent: :restrict_with_error
  has_many :folios, dependent: :destroy
  has_many :stock_levels, dependent: :restrict_with_error
  has_many :shifts, dependent: :restrict_with_error
  has_many :sales, dependent: :restrict_with_error
  has_many :minimums, dependent: :destroy

  validates :cash_limit_cents, numericality: { only_integer: true, greater_than: 0 }
  # How many days between stock counts; blank = no reminder.
  validates :count_interval_days, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  validates :code, presence: true, uniqueness: true, length: { maximum: 10 }
  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :printer, inclusion: { in: PRINTERS }
  validates :network_printer, format: { with: /\A[\w.-]+:\d{1,5}\z/ }, if: -> { printer == "network" }

  scope :active, -> { where(active: true) }

  def self.head_office
    find_by(kind: "head_office")
  end

  def head_office?
    kind == "head_office"
  end

  def warehouse? = kind == "warehouse"

  def till? = !warehouse?

  scope :with_till, -> { where.not(kind: "warehouse") }
  scope :warehouses, -> { where(kind: "warehouse") }

  def cash_limit
    BigDecimal(cash_limit_cents) / 100
  end

  def to_s
    name
  end
end
