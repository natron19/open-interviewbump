module Admin
  class LlmRequestsController < Admin::BaseController
    def index
      @requests = LlmRequest.includes(:user, :ai_template)
                             .order(created_at: :desc)
                             .limit(100)
      @requests = @requests.where(status: params[:status]) if params[:status].present?
      @status_filter = params[:status]
    end
  end
end
