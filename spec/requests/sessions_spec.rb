require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let(:user) { create(:user) }

  describe "GET /sign_in" do
    it "returns 200 for guests" do
      get sign_in_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /sign_in" do
    context "with valid credentials" do
      it "redirects to dashboard" do
        post sign_in_path, params: { email: user.email, password: "password123" }
        expect(response).to redirect_to(dashboard_path)
      end

      it "sets the session user_id" do
        post sign_in_path, params: { email: user.email, password: "password123" }
        expect(session[:user_id]).to eq(user.id)
      end
    end

    context "with invalid credentials" do
      it "returns 422" do
        post sign_in_path, params: { email: user.email, password: "wrongpassword" }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "does not set the session" do
        post sign_in_path, params: { email: user.email, password: "wrongpassword" }
        expect(session[:user_id]).to be_nil
      end
    end
  end

  describe "DELETE /sign_out" do
    it "clears the session and redirects to root" do
      sign_in_as(user)
      delete sign_out_path
      expect(response).to redirect_to(root_path)
      expect(session[:user_id]).to be_nil
    end
  end
end
