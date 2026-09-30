# Quién está trabajando y desde qué sucursal, durante toda la petición.
class Current < ActiveSupport::CurrentAttributes
  attribute :usuario, :sucursal, :modulos, :simbolo
end
