require "rails_helper"

RSpec.describe "JobSeekerProfiles", type: :request do
  let(:user) { create(:user) }

  describe "GET /job_seeker_profile/edit" do
    it "redirects unauthenticated user to sign in" do
      get edit_job_seeker_profile_path
      expect(response).to redirect_to(sign_in_path)
    end

    it "returns 200 when signed in" do
      sign_in_as(user)
      get edit_job_seeker_profile_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /job_seeker_profile" do
    before { sign_in_as(user) }

    it "upserts the profile and redirects to dashboard" do
      patch job_seeker_profile_path, params: { job_seeker_profile: { background_summary: "5 years in Go." } }
      expect(response).to redirect_to(dashboard_path)
      expect(user.reload.job_seeker_profile.background_summary).to eq("5 years in Go.")
    end

    it "updates an existing profile" do
      create(:job_seeker_profile, user: user, background_summary: "Old summary")
      patch job_seeker_profile_path, params: { job_seeker_profile: { background_summary: "New summary" } }
      expect(response).to redirect_to(dashboard_path)
      expect(user.reload.job_seeker_profile.background_summary).to eq("New summary")
    end

    it "re-renders the form when background_summary exceeds 10000 characters" do
      patch job_seeker_profile_path, params: { job_seeker_profile: { background_summary: "a" * 10_001 } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
