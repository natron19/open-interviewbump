class DashboardController < ApplicationController
  def show
    @recent_sessions = current_user.prep_sessions
                                   .order(created_at: :desc)
                                   .limit(5)
                                   .includes(:prep_guide)
    @has_profile = current_user.job_seeker_profile&.background_summary.present?
  end
end
