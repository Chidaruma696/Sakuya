# Document numbering, per branch. The counter goes by DOCUMENT (sale, shift, order…), never by
# the letter: the business chooses the prefix in Settings › Folios and can change it without the
# numbering restarting. It can also use a single running sequence for everything.
class Folio < ApplicationRecord
  belongs_to :branch

  # Which documents are numbered and their default prefix.
  DOCUMENTS = {
    "sale" => "B", "shift" => "C", "refund" => "D", "stock_count" => "K", "receipt" => "RC", "stock_transfer" => "TG", "account_payment" => "AB", "order" => "P"
  }.freeze
  MODES = %w[per_document single].freeze
  PREFIX = /\A[A-Z0-9]{0,4}\z/

  validates :prefix, presence: true, inclusion: { in: DOCUMENTS.keys + [ "single" ] }
  validates :last, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # The branch's next folio for that document, atomically: the database does the increment, not Ruby.
  def self.next_number!(branch, document)
    document = document.to_s
    raise ArgumentError, "unknown document: #{document}" unless DOCUMENTS.key?(document)
    counter = single? ? "single" : document
    transaction do
      folio = find_or_create_by!(branch: branch, prefix: counter)
      where(id: folio.id).update_all("last = last + 1")
      compose(prefix_of(document), folio.reload.last, code: (branch.code if with_branch?))
    end
  end

  def self.single? = Setting["folios.mode"] == "single"
  # The branch code goes in front (MTZ-B-00001): those letters come from the branch, not the document.
  def self.with_branch? = Setting["folios.branch"] == "1"

  # The prefix the document gets: the single one if numbering is a single sequence, otherwise its own.
  def self.prefix_of(document)
    Setting[single? ? "folios.single" : "folios.#{document}"].to_s
  end

  def self.compose(prefix, number, code: nil)
    [ code, prefix, number.to_s.rjust(5, "0") ].compact_blank.join("-")
  end
end
