class RegistrationsController < ApplicationController
  skip_before_action :require_authentication

  rate_limit to: 10, within: 1.minute, by: -> { request.remote_ip },
             with: -> { redirect_to sign_up_path, alert: "Too many attempts. Try again in a minute." }

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      reset_session
      session[:user_id] = @user.id
      redirect_to dashboard_path, notice: "Welcome, #{@user.first_name}!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end
end
