# Tickets en ESC/POS, el idioma de las impresoras térmicas: el mismo ticket de la pantalla, pero en
# bytes que la impresora entiende sin driver. Texto en la página de códigos PC850 (acentos, ñ, ¿,
# ¡); lo que no cabe en ella sale con un sustituto. 32 columnas en papel de 58 mm, 48 en 80 mm.
module EscPos
  ESC = "\e".b
  GS = "\x1D".b

  class Documento
    attr_reader :columnas

    def initialize(columnas:)
      @columnas = columnas
      @bytes = +"".b
      @bytes << ESC << "@" << ESC << "t" << 2.chr # reinicia y elige PC850
    end

    def texto(s)
      @bytes << codificar(s) << "\n"
      self
    end

    def centro = alinear(1)
    def izquierda = alinear(0)

    def negrita(si = true)
      @bytes << ESC << "E" << (si ? 1 : 0).chr
      self
    end

    # Doble de alto y de ancho, para el total.
    def grande(si = true)
      @bytes << GS << "!" << (si ? 0x11 : 0).chr
      self
    end

    def linea(caracter = "-") = texto(caracter * columnas)

    # Texto a la izquierda y cifra a la derecha en el mismo renglón; si no caben, en dos.
    def renglon(izq, der, columnas: self.columnas)
      izq = izq.to_s
      der = der.to_s
      return texto(izq + (" " * (columnas - izq.length - der.length)) + der) if izq.length + der.length < columnas
      texto(izq)
      texto(der.rjust(columnas))
    end

    # Código de barras EAN-13 con los números debajo.
    def ean13(codigo)
      digitos = codigo.to_s.gsub(/\D/, "")
      return self unless digitos.length == 13
      @bytes << GS << "h" << 60.chr << GS << "w" << 2.chr << GS << "H" << 2.chr << GS << "k" << 67.chr << 13.chr << digitos << "\n"
      self
    end

    # Avanza el papel y corta (parcial, para que el ticket no se caiga).
    def cortar
      @bytes << ESC << "d" << 3.chr << GS << "V" << 66.chr << 0.chr
      self
    end

    def to_s = @bytes

    private

    def alinear(n)
      @bytes << ESC << "a" << n.chr
      self
    end

    def codificar(s)
      s.to_s.gsub("€", "EUR").gsub(/[−–—]/, "-").encode("CP850", undef: :replace, invalid: :replace, replace: "?").b
    end
  end

  # El ticket de una venta, con los mismos datos y ajustes que el de la pantalla.
  def self.ticket(venta)
    a = Ajuste.todos
    d = Documento.new(columnas: Ajuste.entero("ticket.ancho") == 58 ? 32 : 48)
    d.centro.negrita.texto(a["negocio.nombre"].presence || venta.sucursal&.nombre).negrita(false)
    [ a["ticket.lema"], (venta.sucursal&.nombre if a["negocio.nombre"].present? && venta.sucursal&.nombre != a["negocio.nombre"]),
      a["negocio.direccion"], a["negocio.telefono"], a["ticket.rfc"] ].compact_blank.each { |l| d.texto(l) }
    d.izquierda.linea
    d.renglon("#{I18n.t("comun.fecha")}: #{I18n.l(venta.created_at, format: :short)}", "")
    d.negrita.texto("#{I18n.t("comun.folio")}: #{venta.folio}").negrita(false)
    d.texto("#{I18n.t("caja.le_atendio")}: #{venta.usuario&.nombre}") if a["ticket.mostrar_cajero"] == "1"
    d.texto("#{I18n.t("caja.cliente")}: #{venta.cliente.nombre}") if venta.cliente
    d.linea
    venta.lineas.includes(:producto, :promocion).each do |l|
      nombre = l.producto.nombre
      nombre += " (#{l.promocion.nombre})" if l.promocion
      nombre += " *" if l.precio_centavos < l.catalogo_centavos
      d.texto(nombre)
      d.renglon("  #{ApplicationController.helpers.cantidad(l.cantidad, l.producto)} x #{Dinero.pesos(l.precio_centavos)}", Dinero.pesos(l.importe_centavos))
    end
    d.linea
    d.negrita.grande.renglon(I18n.t("comun.total").upcase, Dinero.pesos(venta.total_centavos), columnas: d.columnas / 2).grande(false).negrita(false)
    venta.pagos.each { |p| d.renglon(I18n.t("formas_pago.#{p.forma}"), Dinero.pesos(p.monto_centavos)) }
    d.renglon(I18n.t("caja.cambio"), Dinero.pesos(venta.cambio_centavos))
    d.centro.negrita.texto(I18n.t("estados.devuelta").upcase).negrita(false) if venta.estado == "devuelta"
    d.linea(".")
    d.texto(a["ticket.leyenda_devoluciones"].presence || I18n.t("caja.devoluciones_solo_con_ticket"))
    d.ean13(venta.codigo) if a["ticket.mostrar_codigo"] == "1"
    d.texto(a["negocio.pie_ticket"]) if a["negocio.pie_ticket"].present?
    d.cortar.to_s
  end
end
