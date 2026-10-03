class Withdrawal < ApplicationRecord
  belongs_to :shift
  belongs_to :user
  belongs_to :authorized_by, class_name: "User", optional: true

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :reason, presence: true
end
