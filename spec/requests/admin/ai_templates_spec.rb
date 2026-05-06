require "rails_helper"

RSpec.describe "Admin::AiTemplates", type: :request do
  let(:admin)    { create(:user, :admin) }
  let(:user)     { create(:user) }
  let(:template) { create(:ai_template) }

  describe "GET /admin/ai_templates" do
    context "when unauthenticated" do
      it "redirects to sign in" do
        get admin_ai_templates_path
        expect(response).to redirect_to(sign_in_path)
      end
    end

    context "when signed in as non-admin" do
      it "returns 404" do
        sign_in_as(user)
        get admin_ai_templates_path
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when signed in as admin" do
      it "returns 200" do
        sign_in_as(admin)
        get admin_ai_templates_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /admin/ai_templates/:id/edit" do
    context "when signed in as admin" do
      it "returns 200" do
        sign_in_as(admin)
        get admin_edit_ai_template_path(template)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as non-admin" do
      it "returns 404" do
        sign_in_as(user)
        get admin_edit_ai_template_path(template)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PATCH /admin/ai_templates/:id" do
    context "when signed in as admin" do
      it "updates the template and redirects with flash" do
        sign_in_as(admin)
        patch admin_ai_template_path(template),
              params: { ai_template: { description: "Updated description" } }
        expect(response).to redirect_to(admin_edit_ai_template_path(template))
        expect(flash[:notice]).to eq("Template saved.")
        expect(template.reload.description).to eq("Updated description")
      end

      it "returns 422 with invalid params" do
        sign_in_as(admin)
        patch admin_ai_template_path(template),
              params: { ai_template: { system_prompt: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "POST /admin/ai_templates/:id/test" do
    context "when signed in as non-admin" do
      it "returns 404" do
        sign_in_as(user)
        post admin_test_ai_template_path(template),
             params: { variables: {} },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when signed in as admin" do
      before { sign_in_as(admin) }

      it "returns a Turbo Stream response on success" do
        gemini_returns("AI response text")
        post admin_test_ai_template_path(template),
             params: { variables: { name: "World" } },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("turbo-stream")
      end

      it "returns a Turbo Stream error partial on GeminiError" do
        gemini_raises(GeminiService::TimeoutError)
        post admin_test_ai_template_path(template),
             params: { variables: {} },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("turbo-stream")
      end
    end
  end
end
