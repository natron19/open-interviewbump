require "rails_helper"

# Gemini occasionally drops a brace or bracket even in JSON mode. A JSON template gets one
# retry before the output guard sees the response.
RSpec.describe GeminiService, "JSON retry" do
  let(:user)     { create(:user) }
  let(:template) { create(:ai_template) }
  let(:broken)   { %({"items": [{"a": "x"\n    ,{"a": "y"}]}) }
  let(:valid)    { %({"items": [{"a": "x"}, {"a": "y"}]}) }

  def guard_format(format)
    allow(AiGuardConfig).to receive(:for_template).and_return({ format: format }.compact.with_indifferent_access)
  end

  it "retries once when a JSON template's response won't parse, and logs both calls" do
    guard_format("json")
    calls = 0
    allow_any_instance_of(GeminiService).to receive(:call_gemini) do
      calls += 1
      calls == 1 ? [broken, 100, 50] : [valid, 100, 60]
    end

    expect(GeminiService.generate(template: template.name, user: user)).to eq(valid)
    expect(calls).to eq(2)
    expect(LlmRequest.last).to have_attributes(status: "success", prompt_token_count: 200, response_token_count: 110)
  end

  it "stops after one retry and lets the output guard reject the response" do
    guard_format("json")
    allow_any_instance_of(GeminiService).to receive(:call_gemini).and_return([broken, 100, 50])

    expect { GeminiService.generate(template: template.name, user: user) }
      .to raise_error(GeminiService::OutputGuardError, /not valid JSON/)
    expect(LlmRequest.last.status).to eq("output_blocked")
  end

  it "does not retry valid JSON or templates that aren't JSON" do
    guard_format(nil)
    calls = 0
    allow_any_instance_of(GeminiService).to receive(:call_gemini) { calls += 1; ["plain {text", 10, 5] }

    GeminiService.generate(template: template.name, user: user)
    expect(calls).to eq(1)
  end
end
