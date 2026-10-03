# Export and import all the business rules in one file, under Settings › Advanced options.
class RulesFileController < ApplicationController
  before_action { authorize!("rules.edit") }

  def show
    @in_force = Rule::HOOKS.filter_map { |g| Rule.current(g) }
  end

  def export
    text = RulesFile.export(business: Setting["business.name"].presence || current_branch.name)
    send_data text, filename: "sakuya-rules-#{Date.current}.lisp", type: "text/plain; charset=utf-8"
  end

  def import
    file = params[:file]
    return redirect_to(rules_file_path, alert: t("rules.file.no_file")) unless file.respond_to?(:read)
    touched = RulesFile.import!(file.read.force_encoding("UTF-8"), user: current_user)
    notice = touched.any? ? t("rules.file.imported", hooks: touched.map { |g| t("settings.sections.#{g == "dashboard" ? g : "#{g}_rule"}") }.join(", ")) : t("rules.file.no_changes")
    redirect_to rules_file_path, notice: notice
  rescue Lisp::Error => e
    redirect_to rules_file_path, alert: t("rules.file.not_imported", error: e.message)
  end
end
