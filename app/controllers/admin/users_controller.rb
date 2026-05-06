module Admin
  class UsersController < Admin::BaseController
    def index
      @users          = User.order(created_at: :desc)
      @today_counts   = LlmRequest.today.group(:user_id).count
      @lifetime_counts = LlmRequest.group(:user_id).count
      @last_seen      = LlmRequest.group(:user_id).maximum(:created_at)
    end
  end
end
