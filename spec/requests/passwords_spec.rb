require "rails_helper"

RSpec.describe "Passwords", type: :request do
  let(:user) { create(:user) }

  describe "GET /passwords/new" do
    it "returns 200" do
      get new_password_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /passwords" do
    it "redirects with notice regardless of whether email exists" do
      post passwords_path, params: { email: user.email }
      expect(response).to redirect_to(sign_in_path)
      expect(flash[:notice]).to be_present
    end

    it "redirects with same notice for a nonexistent email" do
      post passwords_path, params: { email: "nobody@example.com" }
      expect(response).to redirect_to(sign_in_path)
      expect(flash[:notice]).to be_present
    end
  end

  describe "GET /passwords/edit" do
    context "with a valid token" do
      let!(:reset) do
        user.password_resets.create!(token: "validtoken123", expires_at: 30.minutes.from_now)
      end

      it "returns 200" do
        get edit_password_path(token: reset.token)
        expect(response).to have_http_status(:ok)
      end
    end

    context "with an expired token" do
      let!(:reset) do
        user.password_resets.create!(token: "expiredtoken", expires_at: 1.hour.ago)
      end

      it "redirects to new password path with alert" do
        get edit_password_path(token: reset.token)
        expect(response).to redirect_to(new_password_path)
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "PATCH /passwords/:token" do
    let!(:reset) do
      user.password_resets.create!(token: "resettoken123", expires_at: 30.minutes.from_now)
    end

    context "with valid params" do
      it "updates the password and signs in the user" do
        patch "/passwords/#{reset.token}",
              params: { user: { password: "newpassword123", password_confirmation: "newpassword123" } }
        expect(response).to redirect_to(dashboard_path)
        expect(session[:user_id]).to eq(user.id)
      end
    end

    context "with mismatched confirmation" do
      it "returns 422" do
        patch "/passwords/#{reset.token}",
              params: { user: { password: "newpassword123", password_confirmation: "different" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
