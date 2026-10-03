# How REPL results are shown: a list of maps as a table, a map as two columns and
# everything else written as it would be in the program.
module ReplHelper
  def repl_cell(v)
    case v
    when nil then content_tag(:span, "nil", class: "text-stone-400")
    when BigDecimal then number_with_precision(v, precision: v.round(2) == v ? 2 : 3, delimiter: ",")
    when String then v
    when Array, Hash then content_tag(:span, Lisp.to_text(v).truncate(120), class: "font-mono text-xs")
    else Lisp.to_text(v)
    end
  end

  def repl_table?(v) = v.is_a?(Array) && v.any? && v.all? { |f| f.is_a?(Hash) }

  def repl_columns(rows) = rows.flat_map(&:keys).uniq
end
