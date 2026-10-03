# What the deciding hooks have in common (closing the till, a line's price…): the rule ends in
# (allow), (to-review reason) or (reject reason) and the core does whatever applies. If the
# business's rule blows up or does not decide, the built-in one decides and the error travels in
# the decision so it gets recorded.
#
# Each hook extends it and defines DEFAULT, REASONS (the keywords it knows how to translate),
# `functions(data)` with what the rule can read, `texts` (its translations section) and
# `interpolate(data)` with what its reasons will carry.
module Hook
  Decision = Data.define(:verdict, :reason, :error) do
    def allows? = verdict == :allow
    def review? = verdict == :review
    def rejects? = verdict == :reject
  end

  # The built-in rule runs without plugins: if one of them breaks something, the built-in one still stands.
  def decide_with(code, data)
    return evaluate(self::DEFAULT, data, plugins: false) if code.blank?
    evaluate(code, data)
  rescue Lisp::Error => e
    evaluate(self::DEFAULT, data, plugins: false).with(error: e.message)
  end

  # Evaluates a program; raises Lisp::Error if it does not end in a decision.
  def evaluate(code, data, plugins: true)
    result = Lisp.run(code, functions: functions(data).merge(decisions(data)), prelude: plugins ? Plugin.prelude : [])
    result.is_a?(Decision) ? result : raise(Lisp::Error, I18n.t("rules.errors.no_decision", value: Lisp.to_text(result)))
  end

  private

  def decisions(data)
    {
      "allow" => -> { Decision.new(verdict: :allow, reason: nil, error: nil) },
      "to-review" => ->(reason) { Decision.new(verdict: :review, reason: reason(reason, data), error: nil) },
      "reject" => ->(reason) { Decision.new(verdict: :reject, reason: reason(reason, data), error: nil) }
    }
  end

  def reason(reason, data)
    case reason
    when String then reason.presence || raise(Lisp::Error, I18n.t("rules.errors.reason"))
    when Symbol
      raise Lisp::Error, I18n.t("rules.errors.unknown_reason", reason: reason, reasons: self::REASONS.join(" :")) unless self::REASONS.include?(reason)
      I18n.t("#{texts}.reasons.#{reason.to_s.underscore}", **interpolate(data))
    else raise Lisp::Error, I18n.t("rules.errors.reason")
    end
  end
end
