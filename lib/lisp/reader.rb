module Lisp
  # Turns text into forms: lists (Array), symbols, numbers, strings and keywords.
  # `;` comments up to the end of the line and 'x is (quote x).
  module Reader
    TOKEN = /\G(?:(?<space>\s+|;[^\n]*)|(?<opens>\()|(?<closes>\))|(?<quote>')|(?<string>"(?:[^"\\]|\\.)*")|(?<atom>[^\s()'";]+)|(?<bad>"))/m
    INTEGER = /\A[-+]?\d+\z/
    DECIMAL = /\A[-+]?\d*\.\d+\z/
    MAX_NESTING = 64 # nested parentheses; more than that is not a rule, it is an accident

    def self.read(text)
      text = text.to_s
      raise ReadError, I18n.t("lisp.errors.too_long", max: MAX_LENGTH) if text.length > MAX_LENGTH
      stack = [ [] ]
      quotes = [ [] ]
      pos = 0
      while pos < text.length
        m = TOKEN.match(text, pos) or raise ReadError, I18n.t("lisp.errors.unreadable", line: line(text, pos))
        if m[:opens]
          raise ReadError, I18n.t("lisp.errors.too_nested", line: line(text, pos)) if stack.size > MAX_NESTING
          stack.push([])
          quotes.push([])
        elsif m[:closes]
          raise ReadError, I18n.t("lisp.errors.extra_close", line: line(text, pos)) if stack.size == 1
          raise ReadError, I18n.t("lisp.errors.quote_before_close", line: line(text, pos)) if quotes.last.any?
          list = stack.pop
          quotes.pop
          add(stack, quotes, list)
        elsif m[:quote]
          quotes.last.push(true)
        elsif m[:string]
          add(stack, quotes, unescape(m[:string][1..-2]))
        elsif m[:atom]
          add(stack, quotes, atom(m[:atom]))
        elsif m[:bad]
          raise ReadError, I18n.t("lisp.errors.unclosed_string", line: line(text, pos))
        end
        pos = m.end(0)
      end
      raise ReadError, I18n.t("lisp.errors.unclosed_parens", count: stack.size - 1) if stack.size > 1
      raise ReadError, I18n.t("lisp.errors.quote_at_end") if quotes.last.any?
      stack.first
    end

    def self.add(stack, quotes, form)
      form = [ Sym.new("quote"), form ] while quotes.last.pop
      stack.last.push(form)
    end

    def self.atom(text)
      case text
      when INTEGER then Integer(text, 10)
      when DECIMAL then BigDecimal(text)
      when "true" then true
      when "false" then false
      when "nil" then nil
      when /\A:[^:]+\z/ then text[1..].to_sym
      else Sym.new(text)
      end
    end

    def self.unescape(text)
      text.gsub(/\\(.)/) { { "n" => "\n", "t" => "\t" }.fetch($1, $1) }
    end

    def self.line(text, pos) = text[0, pos].count("\n") + 1

    private_class_method :add, :atom, :unescape, :line
  end
end
