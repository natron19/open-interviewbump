require "rails_helper"

RSpec.describe "Registrations", type: :request do
  describe "GET /sign_up" do
    it "returns 200 for guests" do
      get sign_up_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /sign_up" do
    let(:valid_params) do
      { user: { name: "New User", email: "new@example.com",
                password: "password123", password_confirmation: "password123" } }
    end

    context "with valid params" do
      it "creates a user" do
        expect { post sign_up_path, params: valid_params }.to change(User, :count).by(1)
      end

      it "sets the session and redirects to dashboard" do
        post sign_up_path, params: valid_params
        expect(response).to redirect_to(dashboard_path)
        expect(session[:user_id]).to be_present
      end
    end

    context "with an invalid email" do
      it "returns 422 and does not create a user" do
        params = valid_params.deep_merge(user: { email: "not-an-email" })
        expect { post sign_up_path, params: params }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with a duplicate email" do
      it "returns 422" do
        create(:user, email: "new@example.com")
        post sign_up_path, params: valid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
