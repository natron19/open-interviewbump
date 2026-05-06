class SessionsController < ApplicationController
  skip_before_action :require_authentication

  rate_limit to: 10, within: 1.minute, by: -> { request.remote_ip },
             with: -> { redirect_to sign_in_path, alert: "Too many attempts. Try again in a minute." }

  def new
  end

  def create
    user = User.find_by(email: params[:email].to_s.downcase)
    if user&.authenticate(params[:password])
      reset_session
      session[:user_id] = user.id
      redirect_to dashboard_path, notice: "Welcome back, #{user.first_name}!"
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "You've been signed out."
  end
end
