# Las reglas de un negocio en un solo archivo .lisp, para respaldarlas o llevarlas a otra
# instalación. Es texto que se lee y se edita a mano: cada regla vigente va debajo de su cabecera.
#
#   ;;; hook: corte (contract 1)
#   (if (or (= (limit) 0) …) (allow) (reject :over-limit))
module ArchivoReglas
  CABECERA = /\A;;; hook: ([a-z]+) \(contract (\d+)\)\s*\z/

  Leida = Data.define(:gancho, :version, :codigo)

  def self.exportar(negocio:, fecha: Time.current)
    partes = Regla::GANCHOS.filter_map do |gancho|
      regla = Regla.vigente(gancho) or next
      ";;; hook: #{gancho} (contract #{regla.version})\n#{regla.codigo.strip}\n"
    end
    ";; Sakuya rules · #{negocio} · #{fecha.strftime("%Y-%m-%d %H:%M")}\n\n#{partes.join("\n")}"
  end

  # Lee el archivo y revisa que cada regla se pueda leer; levanta Lisp::Error con todo lo que
  # falló, y entonces no se importa nada.
  def self.leer(texto)
    leidas = []
    errores = []
    texto.to_s.each_line do |linea|
      if (m = CABECERA.match(linea.chomp))
        leidas << { gancho: m[1], version: m[2].to_i, codigo: +"" }
      elsif leidas.any?
        leidas.last[:codigo] << linea
      end
    end
    raise Lisp::Error, I18n.t("reglas.archivo.vacio") if leidas.empty?
    leidas.each do |l|
      l[:codigo] = l[:codigo].strip
      next errores << I18n.t("reglas.archivo.gancho", gancho: l[:gancho]) unless Regla::GANCHOS.include?(l[:gancho])
      next errores << I18n.t("reglas.archivo.repetido", gancho: l[:gancho]) if leidas.count { |o| o[:gancho] == l[:gancho] } > 1
      Lisp::Lector.leer(l[:codigo])
    rescue Lisp::Error => e
      errores << "#{l[:gancho]}: #{e.message}"
    end
    raise Lisp::Error, errores.uniq.join("; ") if errores.any?
    leidas.map { |l| Leida.new(**l) }
  end

  # Asienta como versión nueva cada regla que cambió; devuelve los ganchos que se tocaron.
  def self.importar!(texto, usuario:)
    leidas = leer(texto)
    Regla.transaction do
      leidas.filter_map do |l|
        next if Regla.vigente(l.gancho)&.codigo == l.codigo
        Regla.create!(gancho: l.gancho, codigo: l.codigo, version: l.version, usuario: usuario)
        l.gancho
      end
    end
  end
end
