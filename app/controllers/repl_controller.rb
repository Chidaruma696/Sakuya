# The read-only REPL, under Settings › Advanced options. What is typed is evaluated against the
# live data (the head office sees every branch; a store, its own) and nothing is saved, except
# the latest queries in the session so they can be reused.
class ReplController < ApplicationController
  HISTORY = 10 # lives in the session cookie: few and short

  before_action { authorize!("rules.edit") }

  def show
    @text = params[:text].presence || "(sales)"
    @history = session[:repl] || []
    @reports = reports
  end

  # Who asked the REPL what, most recent first.
  def log
    @queries = ReplQuery.includes(:user, :branch).order(id: :desc).limit(200)
  end

  def evaluate
    @text = params[:text].to_s
    begin
      @value = Repl.evaluate(@text, branches: current_branch.head_office? ? Branch.all : [ current_branch ])
      @evaluated = true
    rescue Lisp::Error => e
      @error = e.message
    end
    session[:repl] = ([ @text.strip ] + (session[:repl] || [])).uniq.first(HISTORY) if @text.present? && @text.size <= 300
    # Outside the write lock: the log does get written.
    ReplQuery.create!(user: current_user, branch: current_branch, text: @text.strip, ok: @error.nil?) if @text.present?
    @history = session[:repl]
    @reports = reports
    render :show, status: @error ? :unprocessable_entity : :ok
  end

  private

  # The reports that enabled plugins bring; if one no longer parses, it does not get in the REPL's way.
  def reports
    Plugin.reports
  rescue Lisp::Error
    []
  end
end
