# A program in Sakuya's Lisp hooked into a point in the system. It is never edited or deleted:
# saving records a new version, and going back records the old one again.
class Rule < ApplicationRecord
  self.table_name = "rules"
  # Each hook and the module that holds its contract (its VERSION).
  CONTRACTS = { "dashboard" => "Dashboard", "shift" => "ShiftRule", "price" => "PriceRule", "withdrawal" => "WithdrawalRule",
                "movement" => "MovementRule", "invoice" => "InvoiceRule", "receipt" => "ReceiptRule", "sale" => "SaleRule", "credit" => "CreditRule" }.freeze
  HOOKS = CONTRACTS.keys.freeze

  belongs_to :user

  validates :hook, inclusion: { in: HOOKS }
  validates :code, presence: true, length: { maximum: Lisp::MAX_LENGTH }

  scope :for_hook, ->(hook) { where(hook: hook).order(id: :desc) }

  # When saving, today's contract version; when restoring or importing, the one it came with.
  attribute :version, :integer, default: nil
  before_validation(on: :create) { self.version ||= self.class.contract(hook) if HOOKS.include?(hook) }

  before_update { raise ActiveRecord::ReadOnlyRecord, "rules cannot be edited: record a new version" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "rules cannot be deleted" }

  def self.current(hook) = for_hook(hook).first

  # The contract version Sakuya has today for that hook.
  def self.contract(hook) = CONTRACTS.fetch(hook).constantize::VERSION

  # It was written for an earlier contract: it may no longer read or answer what the hook expects.
  def old? = version < self.class.contract(hook)
end
