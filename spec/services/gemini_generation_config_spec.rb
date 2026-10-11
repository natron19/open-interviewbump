require "rails_helper"

# gemini-2.5 thinking tokens count against maxOutputTokens. The thinking budget is capped and
# added on top of the template's limit, so thinking can't crowd out the answer.
RSpec.describe GeminiService, ".generation_config" do
  let(:template) { build(:ai_template, name: "plain_text_v1", model: "gemini-2.5-flash", max_output_tokens: 3000, temperature: 0.4) }

  before { stub_const("GeminiService::THINKING_BUDGET", 1024) }

  it "caps thinking and keeps the template's limit for the answer" do
    config = described_class.generation_config(template, json: false)

    expect(config).to include(maxOutputTokens: 4024, temperature: 0.4, thinkingConfig: { thinkingBudget: 1024 })
    expect(config).not_to have_key(:responseMimeType)
  end

  it "asks for a JSON response when the template's guard rules expect JSON" do
    allow(AiGuardConfig).to receive(:for_template).with("plain_text_v1").and_return({ format: "json" }.with_indifferent_access)

    expect(described_class.generation_config(template)[:responseMimeType]).to eq("application/json")
  end

  it "leaves thinking alone for models that don't think" do
    template.model = "gemini-2.0-flash"

    expect(described_class.generation_config(template, json: false)).to eq(maxOutputTokens: 3000, temperature: 0.4)
  end

  it "keeps the minimum budget gemini-2.5-pro requires" do
    stub_const("GeminiService::THINKING_BUDGET", 0)
    template.model = "gemini-2.5-pro"

    expect(described_class.generation_config(template, json: false)[:thinkingConfig]).to eq(thinkingBudget: 128)
  end

  it "lets Gemini decide when the budget is -1, without raising the limit" do
    stub_const("GeminiService::THINKING_BUDGET", -1)

    expect(described_class.generation_config(template, json: false)).to include(maxOutputTokens: 3000, thinkingConfig: { thinkingBudget: -1 })
  end
end
