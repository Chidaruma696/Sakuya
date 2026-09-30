# Los modelos y tablas de Sakuya están en español: Rails necesita saber cómo se pluralizan.
# Las reglas inglesas de Rails dejan "etiqueta" en singular (cree que es un plural latino) y
# hacen "etiquetum" al singularizar, así que aquí mandan las reglas del español.
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.plural(/([aeiouáéíóú])$/i, '\1s')
  inflect.singular(/([aeiouáéíóú])s$/i, '\1')
  inflect.plural(/([lnrd])$/i, '\1es')
  inflect.singular(/([lnrd])es$/i, '\1')
  inflect.irregular "sucursal", "sucursales"
  inflect.irregular "rol", "roles"
  inflect.irregular "sesion", "sesiones"
  inflect.irregular "devolucion", "devoluciones"
  inflect.irregular "recepcion", "recepciones"
  inflect.irregular "linea", "lineas"
  inflect.irregular "revision", "revisiones"
  inflect.irregular "supervision", "supervisiones"
  inflect.irregular "tipo_canastilla", "tipos_canastilla"
  inflect.uncountable %w[codigo_barras codigos_barras]
end
