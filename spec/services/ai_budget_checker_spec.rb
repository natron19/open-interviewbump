require "rails_helper"

RSpec.describe AiBudgetChecker do
  let(:user)     { create(:user) }
  let(:template) { create(:ai_template) }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("AI_CALLS_PER_USER_PER_DAY", "50").and_return("3")
  end

  describe ".check!" do
    it "passes when under the daily limit" do
      create_list(:llm_request, 2, user: user, ai_template: template, created_at: Time.current)
      expect { AiBudgetChecker.check!(user) }.not_to raise_error
    end

    it "raises BudgetExceededError at the daily limit" do
      create_list(:llm_request, 3, user: user, ai_template: template, created_at: Time.current)
      expect { AiBudgetChecker.check!(user) }
        .to raise_error(GeminiService::BudgetExceededError)
    end

    it "does not count requests from yesterday" do
      create_list(:llm_request, 3, user: user, ai_template: template, created_at: 25.hours.ago)
      expect { AiBudgetChecker.check!(user) }.not_to raise_error
    end

    it "does not count requests from other users" do
      other_user = create(:user)
      create_list(:llm_request, 3, user: other_user, ai_template: template, created_at: Time.current)
      expect { AiBudgetChecker.check!(user) }.not_to raise_error
    end
  end

  describe "#remaining_calls" do
    it "returns the correct remaining count" do
      create(:llm_request, user: user, ai_template: template, created_at: Time.current)
      expect(AiBudgetChecker.new(user).remaining_calls).to eq(2)
    end

    it "returns 0 when limit is reached" do
      create_list(:llm_request, 3, user: user, ai_template: template, created_at: Time.current)
      expect(AiBudgetChecker.new(user).remaining_calls).to eq(0)
    end
  end
end
