# The application version and the commit it was built from, for "About".
module Sakuya
  VERSION = "0.1.0"
  COMMIT = begin
    `git -C #{Rails.root} rev-parse --short HEAD 2>/dev/null`.strip.presence || "?"
  rescue StandardError
    "?"
  end
  COMMIT_DATE = begin
    `git -C #{Rails.root} log -1 --format=%cs 2>/dev/null`.strip.presence
  rescue StandardError
    nil
  end
end
