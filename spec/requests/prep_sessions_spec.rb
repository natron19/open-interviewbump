require "rails_helper"

RSpec.describe "PrepSessions", type: :request do
  let(:user)  { create(:user) }
  let(:other) { create(:user) }

  describe "GET /prep_sessions" do
    it "redirects unauthenticated user to sign in" do
      get prep_sessions_path
      expect(response).to redirect_to(sign_in_path)
    end

    it "returns 200 and only the current user's sessions" do
      sign_in_as(user)
      my_session    = create(:prep_session, user: user,  company: "MyCompany")
      other_session = create(:prep_session, user: other, company: "OtherCorp")

      get prep_sessions_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(my_session.company)
      expect(response.body).not_to include(other_session.company)
    end
  end

  describe "POST /prep_sessions" do
    before { sign_in_as(user) }

    context "with valid params" do
      it "creates a PrepSession with status pending and enqueues PrepGuideJob" do
        expect {
          post prep_sessions_path, params: { prep_session: { job_title: "Engineer", company: "Stripe" } }
        }.to have_enqueued_job(PrepGuideJob)
          .and change(PrepSession, :count).by(1)

        expect(PrepSession.last.status).to eq("pending")
        expect(response).to redirect_to(prep_session_path(PrepSession.last))
      end
    end

    context "with missing job_title" do
      it "re-renders the form without creating a session" do
        expect {
          post prep_sessions_path, params: { prep_session: { job_title: "", company: "Stripe" } }
        }.not_to change(PrepSession, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /prep_sessions/:id" do
    it "returns 404 for another user's session" do
      session = create(:prep_session, user: other)
      sign_in_as(user)
      get prep_session_path(session)
      expect(response).to have_http_status(:not_found)
    end

    it "renders the in-progress state for a pending session" do
      session = create(:prep_session, user: user, status: "pending")
      sign_in_as(user)
      get prep_session_path(session)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("turbo-frame")
    end

    it "renders the prep guide for a complete session" do
      session = create(:prep_session, :complete, user: user)
      create(:prep_guide, prep_session: session)
      sign_in_as(user)
      get prep_session_path(session)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Likely Interview Questions")
    end
  end

  describe "GET /prep_sessions/:id/export" do
    before { sign_in_as(user) }

    context "with a complete session that has a prep guide" do
      let(:session) { create(:prep_session, :complete, user: user, job_title: "Staff Engineer", company: "Stripe") }
      before { create(:prep_guide, prep_session: session) }

      it "returns 200 with markdown content type" do
        get export_prep_session_path(session)
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to match(%r{text/markdown})
      end

      it "sends a file attachment with a descriptive filename" do
        get export_prep_session_path(session)
        expect(response.headers["Content-Disposition"]).to include("attachment")
        expect(response.headers["Content-Disposition"]).to include("prep-guide-stripe-staff-engineer.md")
      end

      it "includes the job title and company in the markdown body" do
        get export_prep_session_path(session)
        expect(response.body).to include("Staff Engineer")
        expect(response.body).to include("Stripe")
      end

      it "includes all major sections in the markdown" do
        get export_prep_session_path(session)
        expect(response.body).to include("## Likely Interview Questions")
        expect(response.body).to include("## Company-Specific Signals")
        expect(response.body).to include("## Smart Questions to Ask")
        expect(response.body).to include("## Watch Out")
        expect(response.body).to include("## Sources")
      end

      it "includes STAR outline fields" do
        get export_prep_session_path(session)
        expect(response.body).to include("**Situation:**")
        expect(response.body).to include("**Task:**")
        expect(response.body).to include("**Action:**")
        expect(response.body).to include("**Result:**")
      end
    end

    context "with a session that has no prep guide" do
      let(:session) { create(:prep_session, user: user, status: "pending") }

      it "redirects back to the session page" do
        get export_prep_session_path(session)
        expect(response).to redirect_to(prep_session_path(session))
      end
    end

    context "for another user's session" do
      let(:other_session) { create(:prep_session, :complete, user: other) }

      it "returns 404" do
        get export_prep_session_path(other_session)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /prep_sessions/:id/export unauthenticated" do
    it "redirects to sign in" do
      session = create(:prep_session, :complete, user: user)
      get export_prep_session_path(session)
      expect(response).to redirect_to(sign_in_path)
    end
  end

  describe "DELETE /prep_sessions/:id" do
    before { sign_in_as(user) }

    it "destroys the session and redirects to index" do
      session = create(:prep_session, user: user)
      expect {
        delete prep_session_path(session)
      }.to change(PrepSession, :count).by(-1)
      expect(response).to redirect_to(prep_sessions_path)
    end

    it "returns 404 for another user's session" do
      session = create(:prep_session, user: other)
      delete prep_session_path(session)
      expect(response).to have_http_status(:not_found)
    end
  end
end
