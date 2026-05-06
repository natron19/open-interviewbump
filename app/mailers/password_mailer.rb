class PasswordMailer < ApplicationMailer
  def reset(user, token)
    @user  = user
    @token = token
    @url   = edit_password_url(token: token)
    mail to: @user.email, subject: "Reset your #{ENV.fetch('APP_NAME', 'Open Demo Starter')} password"
  end
end
