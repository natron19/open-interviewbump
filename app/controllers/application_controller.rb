class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :set_current_user
  before_action :require_authentication

  helper_method :current_user, :signed_in?

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  private

  def set_current_user
    Current.user = current_user
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def signed_in?
    current_user.present?
  end

  def require_authentication
    unless signed_in?
      redirect_to sign_in_path, alert: "Please sign in to continue."
    end
  end

  def require_admin
    render file: Rails.public_path.join("404.html"), status: :not_found unless current_user&.admin?
  end

  def record_not_found
    redirect_to root_path, alert: "That record could not be found."
  end
end
