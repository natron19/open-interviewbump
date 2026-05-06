module Admin
  class BaseController < ApplicationController
    before_action :require_admin

    private

    def require_admin
      unless current_user&.admin?
        render file: Rails.public_path.join("404.html"), status: :not_found
      end
    end
  end
end
