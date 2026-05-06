class PrepSessionsController < ApplicationController
  before_action :set_prep_session, only: [:show, :status, :export, :destroy]

  def index
    @prep_sessions = current_user.prep_sessions.order(created_at: :desc).includes(:prep_guide)
  end

  def new
    @prep_session = PrepSession.new(
      job_title: params[:job_title],
      company:   params[:company]
    )
    @has_profile = current_user.job_seeker_profile&.background_summary.present?
  end

  def create
    @prep_session = current_user.prep_sessions.build(session_params)
    @prep_session.status = "pending"

    if @prep_session.save
      PrepGuideJob.perform_later(@prep_session.id)
      redirect_to prep_session_path(@prep_session)
    else
      @has_profile = current_user.job_seeker_profile&.background_summary.present?
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @prep_guide = @prep_session.prep_guide
  end

  def status
    @prep_guide = @prep_session.prep_guide
    # Responds to HTML (Turbo Frame reload via polling controller)
  end

  def export
    guide = @prep_session.prep_guide
    return redirect_to prep_session_path(@prep_session), alert: "Prep guide not ready yet." unless guide

    filename = "prep-guide-#{@prep_session.company.parameterize}-#{@prep_session.job_title.parameterize}.md"
    send_data build_markdown(guide, @prep_session), filename: filename, type: "text/markdown", disposition: "attachment"
  end

  def destroy
    @prep_session.destroy
    redirect_to prep_sessions_path, notice: "Prep session deleted."
  end

  private

  def set_prep_session
    @prep_session = current_user.prep_sessions.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end

  def session_params
    params.require(:prep_session).permit(:job_title, :company, :job_description)
  end

  def build_markdown(guide, prep_session)
    questions     = JSON.parse(guide.likely_questions)
    star_outlines = JSON.parse(guide.star_outlines)
    signals       = JSON.parse(guide.company_signals)
    questions_ask = JSON.parse(guide.questions_to_ask)
    sources       = JSON.parse(guide.sources)

    lines = []
    lines << "# Prep Guide: #{prep_session.job_title} at #{prep_session.company}"
    lines << ""
    lines << "> AI-generated content based on publicly available sources. Verify before acting."
    lines << ""

    lines << "## Likely Interview Questions"
    lines << ""
    questions.each_with_index do |question, i|
      outline = star_outlines[i] || {}
      lines << "### #{i + 1}. #{question}"
      lines << ""
      if outline["situation"].present?
        lines << "**Situation:** #{outline["situation"]}"
        lines << ""
        lines << "**Task:** #{outline["task"]}"
        lines << ""
        lines << "**Action:** #{outline["action"]}"
        lines << ""
        lines << "**Result:** #{outline["result"]}"
      else
        lines << "_No outline available for this question._"
      end
      lines << ""
    end

    lines << "## Company-Specific Signals"
    lines << ""
    signals.each { |s| lines << "- #{s}" }
    lines << ""

    lines << "## Smart Questions to Ask"
    lines << ""
    questions_ask.each_with_index { |q, i| lines << "#{i + 1}. #{q}" }
    lines << ""

    lines << "## Watch Out"
    lines << ""
    lines << guide.watch_out
    lines << ""

    unless sources.empty?
      lines << "## Sources"
      lines << ""
      sources.each { |url| lines << "- #{url}" }
      lines << ""
    end

    lines.join("\n")
  end
end
