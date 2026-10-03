# Who is working and from which branch, for the whole request.
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :branch, :features, :symbol
end
