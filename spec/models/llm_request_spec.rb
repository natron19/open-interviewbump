require "rails_helper"

RSpec.describe LlmRequest, type: :model do
  describe "associations" do
    it "belongs to user" do
      req = create(:llm_request)
      expect(req.user).to be_a(User)
    end

    it "belongs to ai_template (optional)" do
      req = build(:llm_request, ai_template: nil)
      expect(req).to be_valid
    end
  end

  describe "validations" do
    it "rejects invalid status" do
      expect(build(:llm_request, status: "invalid_status")).not_to be_valid
    end

    it "accepts all defined statuses" do
      LlmRequest::STATUSES.each do |status|
        expect(build(:llm_request, status: status)).to be_valid
      end
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let(:template) { create(:ai_template) }

    describe ".today" do
      it "returns requests created today" do
        today_req = create(:llm_request, user: user, ai_template: template, created_at: Time.current)
        old_req   = create(:llm_request, user: user, ai_template: template, created_at: 2.days.ago)
        expect(LlmRequest.today).to include(today_req)
        expect(LlmRequest.today).not_to include(old_req)
      end
    end

    describe ".this_week" do
      it "returns requests from the past week" do
        recent = create(:llm_request, user: user, ai_template: template, created_at: 3.days.ago)
        old    = create(:llm_request, user: user, ai_template: template, created_at: 8.days.ago)
        expect(LlmRequest.this_week).to include(recent)
        expect(LlmRequest.this_week).not_to include(old)
      end
    end

    describe ".successful" do
      it "returns only success status records" do
        success = create(:llm_request, user: user, ai_template: template, status: "success")
        error   = create(:llm_request, :error, user: user, ai_template: template)
        expect(LlmRequest.successful).to include(success)
        expect(LlmRequest.successful).not_to include(error)
      end
    end

    describe ".failed" do
      it "returns error, timeout, gatekeeper_blocked, budget_exceeded" do
        error   = create(:llm_request, :error, user: user, ai_template: template)
        timeout = create(:llm_request, :timeout, user: user, ai_template: template)
        success = create(:llm_request, user: user, ai_template: template, status: "success")
        expect(LlmRequest.failed).to include(error, timeout)
        expect(LlmRequest.failed).not_to include(success)
      end
    end

    describe ".recent" do
      it "returns records ordered by created_at descending, limited to 100" do
        create_list(:llm_request, 3, user: user, ai_template: template)
        results = LlmRequest.recent
        expect(results.size).to be <= 100
        expect(results.first.created_at).to be >= results.last.created_at
      end
    end
  end
end
