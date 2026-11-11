# The only door to a customer's count of returnable containers outside a sale (the sale's own
# pieces go through Till.checkout!, in the sale's transaction): pieces that come back loose,
# pieces written off, and loose entries. Everything is whole pieces and insert only.
module Returnables
  class Error < StandardError; end

  # More pieces are coming back than the customer owes. Not reported: most of the time it is a
  # typing mistake. `over` is [{ kind:, name:, owed:, back: }].
  class MoreThanOwed < Error
    attr_reader :over

    def initialize(over)
      @over = over
      super(over.map { |o| I18n.t("returnables.errors.more_than_owed", kind: o[:name], owed: o[:owed], back: o[:back]) }.join("; "))
    end
  end

  MAX_PIECES = 99_999

  # A number of pieces as it comes from a screen: a whole number, zero or more.
  def self.pieces!(value)
    return 0 if value.blank?
    Integer(value.to_s.strip, 10).tap { |n| raise ArgumentError unless n.between?(0, MAX_PIECES) }
  rescue ArgumentError, TypeError
    raise Error, I18n.t("returnables.errors.pieces", value: value.to_s.truncate(20))
  end

  # The display name of a kind: the declared one, or its key if the rule no longer declares it.
  def self.name(kind, kinds = ReturnableRule.kinds) = kinds[kind.to_s]&.name || kind.to_s

  # What the products on a ticket release, { "kind" => pieces }, each line counted on its own.
  # lines: [[product, quantity]]. Only kinds the rule declares count.
  def self.released(lines, kinds = ReturnableRule.kinds)
    return {} if kinds.empty?
    lines.each_with_object(Hash.new(0)) do |(product, quantity), all|
      next unless product.returnable?
      product.returnables.each do |release|
        pieces = kinds.key?(release.kind) ? release.pieces_for(quantity) : 0
        all[release.kind] += pieces if pieces.positive?
      end
    end
  end

  # Pieces a customer brings back without buying. Up to what they owe nobody is asked; beyond it,
  # it is stopped unless whoever receives has returnables.in_favor and accepts: then the surplus
  # stays in the customer's favor and the movement is left for review.
  def self.receive!(customer:, kind:, quantity:, user:, branch:, accept_in_favor: false, key: nil)
    recorded(key) do
      pieces = positive!(quantity)
      account = customer.returnable_account
      known!(kind, account)
      owed = account.owed(kind)
      if pieces > owed && !(accept_in_favor && user.can?("returnables.in_favor"))
        raise MoreThanOwed.new([ { kind: kind.to_s, name: name(kind), owed: owed, back: pieces } ])
      end
      movement = move!(customer, kind, -pieces, "back", user: user, branch: branch, key: key)
      if pieces > owed
        Review.open!(movement, user: user, branch: branch, reason: I18n.t("returnables.review.in_favor", kind: name(kind), pieces: pieces - owed, customer: customer.name))
      end
      movement
    end
  end

  # Pieces that will not come back. They leave the count; if the kind declares a value, it is
  # charged to the customer's account (a debt, not a sale: the credit rule is not asked). Every
  # write-off is left for review.
  def self.write_off!(customer:, kind:, quantity:, reason:, user:, branch:, key: nil)
    recorded(key) do
      raise Error, I18n.t("errors.reason_required") if reason.blank?
      pieces = positive!(quantity)
      account = customer.returnable_account
      known!(kind, account)
      raise Error, I18n.t("returnables.errors.write_off_over", kind: name(kind), owed: account.owed(kind)) if pieces > account.owed(kind)
      movement = move!(customer, kind, -pieces, "write_off", user: user, branch: branch, note: reason, key: key)
      value = ReturnableRule.kinds[kind.to_s]&.value_cents.to_i * pieces
      if value.positive?
        customer.credit_movements.create!(kind: "returnable", amount_cents: value, date: Date.current, reference: movement, branch: branch, user: user,
                                           reason: I18n.t("returnables.account.charge", pieces: pieces, kind: name(kind)))
      end
      text = I18n.t(value.positive? ? "returnables.review.write_off_charged" : "returnables.review.write_off_free", reason: reason, amount: Money.format_money(value))
      Review.open!(movement, user: user, branch: branch, reason: text, value_cents: value)
      movement
    end
  end

  # An entry with no sale behind it: pieces the customer already holds ("out") or pieces in their
  # favor ("in_favor"). Only for whoever has returnables.adjust (the screen checks), with a note,
  # and always left for review.
  def self.enter!(customer:, kind:, quantity:, direction:, note:, user:, branch:, key: nil)
    recorded(key) do
      raise Error, I18n.t("returnables.errors.note") if note.blank?
      raise Error, I18n.t("returnables.errors.direction") unless %w[out in_favor].include?(direction)
      pieces = positive!(quantity)
      raise Error, I18n.t("returnables.errors.undeclared", kind: kind) unless ReturnableRule.kinds.key?(kind.to_s)
      movement = move!(customer, kind, direction == "out" ? pieces : -pieces, "entry", user: user, branch: branch, note: note, key: key)
      Review.open!(movement, user: user, branch: branch, reason: I18n.t("returnables.review.entry_#{direction}", note: note, customer: customer.name),
                   value_cents: ReturnableRule.kinds[kind.to_s].value_cents.to_i * pieces)
      movement
    end
  end

  # What a sale's ticket says: [[name, pieces out, pieces back, what the customer owed afterwards]].
  def self.ticket_rows(sale)
    return [] unless sale.is_a?(Sale) && sale.persisted? && sale.customer_id
    moved = ReturnableMovement.where(reference: sale).to_a
    return [] if moved.empty?
    kinds = ReturnableRule.kinds
    moved.group_by(&:kind).map do |kind, movements|
      after = ReturnableMovement.where(customer_id: sale.customer_id, kind: kind).where(id: ..movements.map(&:id).max).sum(:quantity)
      [ name(kind, kinds), movements.select { |m| m.quantity.positive? }.sum(&:quantity), -movements.select { |m| m.quantity.negative? }.sum(&:quantity), after ]
    end
  end

  def self.move!(customer, kind, quantity, reason, user:, branch:, note: nil, reference: nil, key: nil)
    customer.returnable_movements.create!(kind: kind.to_s, quantity: quantity, reason: reason, note: note, date: Date.current, branch: branch, user: user,
                                           reference: reference, key: key.presence)
  end

  # The same form sent twice returns the movement it already recorded.
  def self.recorded(key, &)
    if key.present? && (done = ReturnableMovement.find_by(key: key))
      return done
    end
    ReturnableMovement.transaction(&)
  end

  def self.positive!(quantity)
    pieces!(quantity).tap { |n| raise Error, I18n.t("returnables.errors.pieces", value: quantity.to_s.truncate(20)) unless n.positive? }
  end

  # A kind can move outside a sale if the rule declares it or the customer still has a count of it.
  def self.known!(kind, account)
    raise Error, I18n.t("returnables.errors.undeclared", kind: kind) unless ReturnableRule.kinds.key?(kind.to_s) || account.count(kind) != 0
  end

  private_class_method :recorded, :positive!, :known!
end
