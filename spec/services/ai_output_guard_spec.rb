require "rails_helper"

RSpec.describe AiOutputGuard do
  let(:template) do
    build(:ai_template, name: "guard_spec_v1",
          system_prompt: "You are a careful planning assistant for community organizers. Always answer in plain language.")
  end

  def check(output, input: "")
    AiOutputGuard.check!(output, template: template, input: input)
  end

  it "passes a normal response" do
    expect(check("Here is a three-step plan for your meetup.")).to be true
  end

  it "blocks an empty response" do
    expect { check("  ") }.to raise_error(GeminiService::OutputGuardError, /Empty/)
  end

  it "blocks a response that repeats the system prompt" do
    expect { check("My instructions: #{template.system_prompt}") }
      .to raise_error(GeminiService::OutputGuardError, /system prompt/)
  end

  it "blocks profanity" do
    expect { check("This plan is shit.") }.to raise_error(GeminiService::OutputGuardError, /blocked content/)
  end

  it "blocks PII the model invented" do
    expect { check("SSN 123-45-6789") }.to raise_error(GeminiService::OutputGuardError, /SSN/)
    expect { check("Email jane@acme-corp.io") }.to raise_error(GeminiService::OutputGuardError, /email/)
    expect { check("Card 4111 1111 1111 1111") }.to raise_error(GeminiService::OutputGuardError, /credit card/)
  end

  it "allows PII the user supplied and placeholder emails" do
    expect(check("Replies go to sam@acme.io", input: "my email is sam@acme.io")).to be true
    expect(check("Write to you@example.com")).to be true
  end

  it "allows toll-free organization numbers such as crisis hotlines" do
    expect(check("You can also call 1-800-273-8255 any time.")).to be true
    expect { check("Call Dana at (415) 555-0132") }.to raise_error(GeminiService::OutputGuardError, /phone/)
  end

  it "allows numbers that fail the Luhn check" do
    expect(check("Reference 1234 5678 9012 3456")).to be true
  end

  context "with a JSON template rule" do
    before do
      allow(AiGuardConfig).to receive(:for_template)
        .and_return({ format: "json", required_keys: %w[title steps] }.with_indifferent_access)
    end

    it "accepts fenced JSON with the required keys" do
      expect(check("```json\n{\"title\": \"Plan\", \"steps\": []}\n```")).to be true
    end

    it "blocks invalid JSON" do
      expect { check("{\"title\": ") }.to raise_error(GeminiService::OutputGuardError, /valid JSON/)
    end

    it "blocks JSON missing required keys" do
      expect { check("{\"title\": \"Plan\"}") }.to raise_error(GeminiService::OutputGuardError, /steps/)
    end
  end

  describe ".extract_json" do
    it "pulls JSON out of surrounding prose" do
      expect(AiOutputGuard.extract_json("Sure! {\"a\": 1} Hope that helps.")).to eq("a" => 1)
    end

    it "returns nil when nothing parses" do
      expect(AiOutputGuard.extract_json("no json here")).to be_nil
    end
  end
end
