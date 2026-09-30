# EAN-13 de identidad y utilidades de lectura. El código identifica una fila de etiquetas;
# el peso vive en la base, nunca dentro del código.
module Barcode
  PREFIJOS = { "paquete" => "08", "caja" => "07", "tarima" => "06" }.freeze
  TIPOS_POR_PREFIJO = PREFIJOS.invert.freeze

  def self.digitos(texto)
    texto.to_s.gsub(/\D/, "")
  end

  # Dígito verificador EAN/UPC de una cadena de dígitos (12 para EAN-13).
  def self.verificador(cuerpo)
    suma = cuerpo.each_char.with_index.sum { |c, i| c.to_i * (i.even? ? 1 : 3) }
    (10 - suma % 10) % 10
  end

  def self.ean13(doce)
    raise ArgumentError, I18n.t("errores.barcode.doce_digitos") unless doce.match?(/\A\d{12}\z/)
    doce + verificador(doce).to_s
  end

  def self.valido?(codigo)
    codigo.to_s.match?(/\A\d{13}\z/) && codigo[12].to_i == verificador(codigo[0, 12])
  end

  # Código de identidad: prefijo del tipo (2) + PLU (5) + secuencia (5) + verificador.
  def self.identidad(tipo, plu, secuencia)
    prefijo = PREFIJOS.fetch(tipo)
    raise ArgumentError, I18n.t("errores.barcode.plu_rango") unless (0..99_999).cover?(plu)
    raise ArgumentError, I18n.t("errores.barcode.secuencia_rango") unless (1..99_999).cover?(secuencia)
    ean13(format("%s%05d%05d", prefijo, plu, secuencia))
  end

  # { tipo:, plu:, secuencia: } si el código es una etiqueta de identidad válida; si no, nil.
  def self.decodificar_identidad(codigo)
    return nil unless valido?(codigo)
    tipo = TIPOS_POR_PREFIJO[codigo[0, 2]]
    return nil unless tipo
    { tipo: tipo, plu: codigo[2, 5].to_i, secuencia: codigo[7, 5].to_i }
  end

  # Lo que pudo querer decir el lector: con y sin verificador, con y sin el cero inicial (UPC-A).
  def self.variantes(texto)
    d = digitos(texto)
    return [] if d.empty?
    v = [ d ]
    v << "0#{d}" if d.length == 12
    v << d[1..] if d.length == 13 && d.start_with?("0")
    v << ean13(d) if d.length == 12
    v << ean13("0#{d}") if d.length == 11
    v << d[0, 12] if d.length == 13
    v.uniq
  end
end
