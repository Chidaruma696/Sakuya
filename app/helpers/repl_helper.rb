# Cómo se ve lo que devuelve el REPL: una lista de mapas como tabla, un mapa como dos columnas y
# lo demás escrito como se escribiría en el programa.
module ReplHelper
  def repl_celda(v)
    case v
    when nil then content_tag(:span, "nil", class: "text-stone-400")
    when BigDecimal then number_with_precision(v, precision: v.round(2) == v ? 2 : 3, delimiter: ",")
    when String then v
    when Array, Hash then content_tag(:span, Lisp.a_texto(v).truncate(120), class: "font-mono text-xs")
    else Lisp.a_texto(v)
    end
  end

  def repl_tabla?(v) = v.is_a?(Array) && v.any? && v.all? { |f| f.is_a?(Hash) }

  def repl_columnas(filas) = filas.flat_map(&:keys).uniq
end
