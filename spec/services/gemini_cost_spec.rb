require "rails_helper"

# Cost estimates follow Gemini's paid-tier prices and count thinking tokens as output,
# because Gemini bills them that way even though the visible answer excludes them.
RSpec.describe GeminiService, "cost tracking" do
  let(:service) { described_class.new(template: "any", user: nil) }

  describe "#billed_output_tokens" do
    it "adds thinking tokens to the visible answer tokens" do
      body = { "usageMetadata" => { "promptTokenCount" => 700, "candidatesTokenCount" => 368, "thoughtsTokenCount" => 1500 } }
      expect(service.send(:billed_output_tokens, body)).to eq(1868)
    end

    it "works when the model did not think" do
      body = { "usageMetadata" => { "candidatesTokenCount" => 368 } }
      expect(service.send(:billed_output_tokens, body)).to eq(368)
    end

    it "returns nil when Gemini sent no usage, so the caller can estimate" do
      expect(service.send(:billed_output_tokens, {})).to be_nil
    end
  end

  describe "#estimate_cost" do
    it "prices gemini-2.5-flash at $0.30 in / $2.50 out per million tokens, in cents" do
      expect(service.send(:estimate_cost, 1_000_000, 0, "gemini-2.5-flash")).to eq(30.0)
      expect(service.send(:estimate_cost, 0, 1_000_000, "gemini-2.5-flash")).to eq(250.0)
    end

    it "prices gemini-2.5-pro at $1.25 in / $10 out per million tokens" do
      expect(service.send(:estimate_cost, 1_000_000, 1_000_000, "gemini-2.5-pro")).to eq(1125.0)
    end

    it "falls back to flash prices for an unknown model" do
      expect(service.send(:estimate_cost, 1_000_000, 0, "gemini-x")).to eq(30.0)
    end
  end
end
