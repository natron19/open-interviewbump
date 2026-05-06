class PasswordsController < ApplicationController
  skip_before_action :require_authentication

  rate_limit to: 5, within: 10.minutes, by: -> { request.remote_ip },
             with: -> { redirect_to new_password_path, alert: "Too many requests. Try again later." },
             only: :create

  def new
  end

  def create
    user = User.find_by(email: params[:email].to_s.downcase)
    if user
      token = SecureRandom.urlsafe_base64(32)
      user.password_resets.create!(token: token, expires_at: 30.minutes.from_now)
      PasswordMailer.reset(user, token).deliver_now
    end
    # Always show the same message to prevent email enumeration
    redirect_to sign_in_path,
                notice: "If that email is registered, you'll receive a reset link shortly."
  end

  def edit
    @password_reset = PasswordReset.find_by(token: params[:token])
    unless @password_reset&.valid_for_use?
      redirect_to new_password_path, alert: "That reset link is invalid or has expired."
    end
  end

  def update
    @password_reset = PasswordReset.find_by(token: params[:token])
    unless @password_reset&.valid_for_use?
      redirect_to new_password_path, alert: "That reset link is invalid or has expired."
      return
    end

    user = @password_reset.user
    if user.update(password_params)
      @password_reset.update!(used_at: Time.current)
      reset_session
      session[:user_id] = user.id
      redirect_to dashboard_path, notice: "Password updated. You're now signed in."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def password_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end
