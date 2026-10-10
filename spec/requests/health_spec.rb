require "rails_helper"

RSpec.describe "GET /up/llm", type: :request do
  it "pings Gemini as the seeded admin and reports ok" do
    admin = create(:user, :admin)
    create(:ai_template, name: "health_ping", user_prompt_template: "ping")
    allow(GeminiService).to receive(:generate).and_return("ok")

    get health_llm_path

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("status" => "ok", "response" => "ok")
    expect(GeminiService).to have_received(:generate)
      .with(template: "health_ping", variables: {}, user: admin, trusted: true)
  end

  it "reports unconfigured when the template is not seeded" do
    get health_llm_path

    expect(response.parsed_body["status"]).to eq("unconfigured")
  end

  it "reports unconfigured when no admin user exists" do
    create(:ai_template, name: "health_ping", user_prompt_template: "ping")
    expect(GeminiService).not_to receive(:generate)

    get health_llm_path

    expect(response.parsed_body).to include("status" => "unconfigured", "message" => "no admin user seeded")
  end

  it "reports an error when the call fails" do
    create(:user, :admin)
    create(:ai_template, name: "health_ping", user_prompt_template: "ping")
    allow(GeminiService).to receive(:generate).and_raise(GeminiService::OutputGuardError, "Empty response.")

    get health_llm_path

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body["status"]).to eq("error")
  end
end
