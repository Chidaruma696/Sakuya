# A business's rules in a single .lisp file, to back them up or take them to another
# installation. It is text that can be read and edited by hand: each current rule goes under its header.
#
#   ;;; hook: shift (contract 1)
#   (if (or (= (limit) 0) …) (allow) (reject :over-limit))
module RulesFile
  HEADER = /\A;;; hook: ([a-z]+) \(contract (\d+)\)\s*\z/

  Parsed = Data.define(:hook, :version, :code)

  def self.export(business:, date: Time.current)
    parts = Rule::HOOKS.filter_map do |hook|
      rule = Rule.current(hook) or next
      ";;; hook: #{hook} (contract #{rule.version})\n#{rule.code.strip}\n"
    end
    ";; Sakuya rules · #{business} · #{date.strftime("%Y-%m-%d %H:%M")}\n\n#{parts.join("\n")}"
  end

  # Reads the file and checks that every rule can be read; raises Lisp::Error with everything that
  # failed, and then nothing is imported.
  def self.read(text)
    parsed = []
    errors = []
    text.to_s.each_line do |line|
      if (m = HEADER.match(line.chomp))
        parsed << { hook: m[1], version: m[2].to_i, code: +"" }
      elsif parsed.any?
        parsed.last[:code] << line
      end
    end
    raise Lisp::Error, I18n.t("rules.file.empty") if parsed.empty?
    parsed.each do |l|
      l[:code] = l[:code].strip
      next errors << I18n.t("rules.file.hook", hook: l[:hook]) unless Rule::HOOKS.include?(l[:hook])
      next errors << I18n.t("rules.file.repeated", hook: l[:hook]) if parsed.count { |o| o[:hook] == l[:hook] } > 1
      Lisp::Reader.read(l[:code])
    rescue Lisp::Error => e
      errors << "#{l[:hook]}: #{e.message}"
    end
    raise Lisp::Error, errors.uniq.join("; ") if errors.any?
    parsed.map { |l| Parsed.new(**l) }
  end

  # Records each rule that changed as a new version; returns the hooks that were touched.
  def self.import!(text, user:)
    parsed = read(text)
    Rule.transaction do
      parsed.filter_map do |l|
        next if Rule.current(l.hook)&.code == l.code
        Rule.create!(hook: l.hook, code: l.code, version: l.version, user: user)
        l.hook
      end
    end
  end
end
