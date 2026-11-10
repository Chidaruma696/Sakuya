# The application version and the commit it was built from, for "About".
module Sakuya
  VERSION = "0.1.0"
  COMMIT = begin
    IO.popen([ "git", "-C", Rails.root.to_s, "rev-parse", "--short", "HEAD" ], err: File::NULL, &:read).strip.presence || "?"
  rescue StandardError
    "?"
  end
  COMMIT_DATE = begin
    IO.popen([ "git", "-C", Rails.root.to_s, "log", "-1", "--format=%cs" ], err: File::NULL, &:read).strip.presence
  rescue StandardError
    nil
  end
end
