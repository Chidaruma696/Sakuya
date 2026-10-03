# Sending bytes to a network thermal printer: open its port (almost always 9100), write and
# close. If it does not answer within a few seconds, that is an error the till shows.
module Printer
  class Error < StandardError; end

  WAIT = 3

  def self.deliver!(address, bytes)
    host, port = address.to_s.split(":")
    raise Error, I18n.t("errors.printer.no_address") if host.blank? || port.blank?
    Socket.tcp(host, port.to_i, connect_timeout: WAIT) do |s|
      s.write(bytes)
      s.close_write
    end
    true
  rescue SystemCallError, SocketError, IOError, Errno::ETIMEDOUT => e
    raise Error, I18n.t("errors.printer.no_answer", address: address, error: e.message)
  end
end
