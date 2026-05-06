module AuthenticationHelpers
  def sign_in_as(user)
    post sign_in_path, params: { email: user.email, password: "password123" }
  end
end
