# Plugins en Lisp, en Ajustes › Opciones avanzadas: subir el archivo, ver qué trae, encenderlo,
# apagarlo o quitarlo.
class PluginsController < ApplicationController
  before_action { autorizar!("reglas.editar") }

  def index
    @plugins = Plugin.order(:identificador).includes(:usuario)
  end

  def create
    archivo = params[:archivo]
    return redirect_to(plugins_path, alert: t("reglas.archivo.sin_archivo")) unless archivo.respond_to?(:read)
    plugin = Plugin.instalar!(archivo.read.force_encoding("UTF-8"), usuario: usuario_actual)
    redirect_to plugins_path, notice: t(plugin.activo ? "plugins.avisos.actualizado" : "plugins.avisos.instalado", nombre: plugin.nombre)
  rescue Lisp::Error, ActiveRecord::RecordInvalid => e
    redirect_to plugins_path, alert: t("plugins.avisos.no_se_instalo", error: e.message)
  end

  def alternar
    plugin = Plugin.find(params[:id])
    plugin.update!(activo: !plugin.activo)
    redirect_to plugins_path, notice: t(plugin.activo ? "plugins.avisos.encendido" : "plugins.avisos.apagado", nombre: plugin.nombre)
  end

  def destroy
    plugin = Plugin.find(params[:id])
    plugin.destroy!
    redirect_to plugins_path, notice: t("plugins.avisos.quitado", nombre: plugin.nombre)
  end
end
