module Admin
  class DashboardController < Admin::BaseController
    def show
      @total_users     = User.count
      @calls_today     = LlmRequest.today.count
      @calls_this_week = LlmRequest.this_week.count
      @total_templates = AiTemplate.count
      @recent_errors   = LlmRequest.failed.where(created_at: 24.hours.ago..Time.current).count
    end
  end
end
