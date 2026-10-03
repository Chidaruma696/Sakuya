# Mandar bytes a una impresora térmica de red: se abre su puerto (casi siempre el 9100), se escribe
# y se cierra. Si no contesta en unos segundos, es un error que la caja enseña.
module Impresora
  class Error < StandardError; end

  ESPERA = 3

  def self.enviar!(direccion, bytes)
    host, puerto = direccion.to_s.split(":")
    raise Error, I18n.t("errores.impresora.sin_direccion") if host.blank? || puerto.blank?
    Socket.tcp(host, puerto.to_i, connect_timeout: ESPERA) do |s|
      s.write(bytes)
      s.close_write
    end
    true
  rescue SystemCallError, SocketError, IOError, Errno::ETIMEDOUT => e
    raise Error, I18n.t("errores.impresora.no_contesta", direccion: direccion, error: e.message)
  end
end
