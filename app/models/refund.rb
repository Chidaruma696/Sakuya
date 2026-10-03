class Refund < ApplicationRecord
  belongs_to :sale
  belongs_to :branch
  belongs_to :shift, optional: true
  belongs_to :user
  has_many :lines, class_name: "RefundLine", dependent: :restrict_with_error, inverse_of: :refund

  before_validation :assign_folio, on: :create

  validates :folio, presence: true, uniqueness: { scope: :branch_id }
  validates :reason, presence: true
  validates :total_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def to_s
    folio
  end

  private

  def assign_folio
    self.branch ||= shift&.branch || sale&.branch
    self.folio ||= Folio.next_number!(branch, "refund") if branch
  end
end
