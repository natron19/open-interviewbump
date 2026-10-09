require "rails_helper"

RSpec.describe SecretRedactor do
  let(:key) { "AIzaSyTESTONLY_0123456789abcdefghijklmno" }

  around do |example|
    original = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = key
    example.run
  ensure
    ENV["GEMINI_API_KEY"] = original
  end

  it "masks the value of a credential ENV variable wherever it appears" do
    expect(described_class.redact("failed with #{key} attached")).to eq("failed with [REDACTED] attached")
  end

  it "masks a key in a query string" do
    expect(described_class.redact("POST https://x.test/v1?alt=json&key=abc123def")).to eq("POST https://x.test/v1?alt=json&key=[REDACTED]")
  end

  it "masks a Google-shaped key that is not in ENV" do
    expect(described_class.redact("got AIzaSyOTHERKEY_abcdefghijklmnopqrstuvwxyz0")).to eq("got [REDACTED]")
  end

  it "masks bearer tokens and the x-goog-api-key header" do
    text = 'Authorization: Bearer sk-live-abcdef123456 {"x-goog-api-key"=>"zzzzzzzzzz"}'
    expect(described_class.redact(text)).to eq('Authorization: Bearer [REDACTED] {"x-goog-api-key"=>"[REDACTED]"}')
  end

  it "leaves ordinary text and blanks alone" do
    expect(described_class.redact("API key not valid. Please pass a valid API key.")).to eq("API key not valid. Please pass a valid API key.")
    expect(described_class.redact(nil)).to be_nil
  end
end
