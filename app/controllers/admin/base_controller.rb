module Admin
  class BaseController < ApplicationController
    pestana :admin

    private

    # `ruta_ok` puede ser un proc, para rutas que necesitan el id recién creado.
    def guardar(registro, ruta_ok, aviso)
      if registro.save
        redirect_to (ruta_ok.respond_to?(:call) ? ruta_ok.call : ruta_ok), notice: aviso
      else
        flash.now[:alert] = registro.errors.full_messages.join(", ")
        render(registro.new_record? ? :new : :edit, status: :unprocessable_entity)
      end
    end
  end
end
