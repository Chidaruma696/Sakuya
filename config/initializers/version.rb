# Versión de la aplicación y de qué commit salió, para el "Acerca de".
module Sakuya
  VERSION = "0.1.0"
  COMMIT = begin
    `git -C #{Rails.root} rev-parse --short HEAD 2>/dev/null`.strip.presence || "?"
  rescue StandardError
    "?"
  end
  COMMIT_FECHA = begin
    `git -C #{Rails.root} log -1 --format=%cs 2>/dev/null`.strip.presence
  rescue StandardError
    nil
  end
end
