# Lisp plugins, under Settings › Advanced options: upload the file, see what it brings, turn it on,
# turn it off or remove it.
class PluginsController < ApplicationController
  before_action { authorize!("rules.edit") }

  def index
    @plugins = Plugin.order(:identifier).includes(:user)
  end

  def create
    file = params[:file]
    return redirect_to(plugins_path, alert: t("rules.file.no_file")) unless file.respond_to?(:read)
    plugin = Plugin.install!(file.read.force_encoding("UTF-8"), user: current_user)
    redirect_to plugins_path, notice: t(plugin.active ? "plugins.notices.updated" : "plugins.notices.installed", name: plugin.name)
  rescue Lisp::Error, ActiveRecord::RecordInvalid => e
    redirect_to plugins_path, alert: t("plugins.notices.not_installed", error: e.message)
  end

  def toggle
    plugin = Plugin.find(params[:id])
    plugin.update!(active: !plugin.active)
    redirect_to plugins_path, notice: t(plugin.active ? "plugins.notices.enabled" : "plugins.notices.disabled", name: plugin.name)
  end

  def destroy
    plugin = Plugin.find(params[:id])
    plugin.destroy!
    redirect_to plugins_path, notice: t("plugins.notices.removed", name: plugin.name)
  end
end
