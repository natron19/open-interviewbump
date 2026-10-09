require "rails_helper"

# The Gemini key travels in the x-goog-api-key header, never in the URL, so it cannot
# show up in an error message, request log, or eval report that records the URL.
RSpec.describe GeminiService, "API key transport" do
  let(:key) { "AIzaSyTESTONLY_0123456789abcdefghijklmno" }
  let(:captured) { [] }
  let(:connection) do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post(/generateContent/) do |env|
        captured << env
        [200, { "Content-Type" => "application/json" },
         { candidates: [{ content: { parts: [{ text: "ok" }] } }] }.to_json]
      end
    end
    Faraday.new do |conn|
      conn.request  :json
      conn.response :json
      conn.adapter  :test, stubs
    end
  end

  around do |example|
    original = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = key
    example.run
  ensure
    ENV["GEMINI_API_KEY"] = original
  end

  it "sends the key as a header and leaves it out of the URL" do
    allow(Faraday).to receive(:new).and_return(connection)
    service = described_class.new(template: create(:ai_template).name, user: create(:user))

    service.send(:call_gemini, create(:ai_template), "hello")

    env = captured.first
    expect(env.request_headers["x-goog-api-key"]).to eq(key)
    expect(env.url.to_s).not_to include(key)
    expect(env.url.query.to_s).not_to include("key=")
  end
end
