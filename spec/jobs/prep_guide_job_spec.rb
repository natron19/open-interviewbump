require "rails_helper"

RSpec.describe PrepGuideJob, type: :job do
  let(:user)         { create(:user) }
  let(:prep_session) { create(:prep_session, user: user) }

  let(:valid_json) do
    {
      likely_questions: [
        "Tell me about a time you scaled a system.",
        "How do you handle ambiguity?",
        "Describe a conflict with a teammate.",
        "What's your approach to code review?",
        "How do you prioritize competing deadlines?"
      ],
      star_outlines: [
        {
          question: "Tell me about a time you scaled a system.",
          situation: "Our monolith was hitting 500ms p99 under peak load.",
          task:      "Reduce latency by 40% without a full rewrite.",
          action:    "Extracted the hot path into an async worker and added a Redis cache layer.",
          result:    "p99 dropped to 200ms; zero downtime deploy."
        }
      ],
      questions_to_ask: [
        "What does the on-call rotation look like for this team?",
        "How do you measure engineering productivity?",
        "What's the biggest technical challenge the team faces this quarter?"
      ],
      watch_out:       "Stripe interviews heavily on distributed systems fundamentals — brush up on CAP theorem and idempotency.",
      company_signals: [
        "Stripe values written communication; expect a doc-based exercise.",
        "Engineers own features end-to-end including on-call."
      ]
    }.to_json
  end

  let(:gemini_result) do
    {
      text:        valid_json,
      sources:     ["https://reddit.com/r/cscareerquestions/stripe-interview"],
      agent_trace: [
        { tool: "search_web", input: "Stripe SWE interview", result_preview: "Found threads.", timestamp: Time.current.iso8601 }
      ]
    }
  end

  before do
    allow(GeminiService).to receive(:generate_with_tools).and_return(gemini_result)
  end

  describe "#perform" do
    context "when GeminiService returns valid JSON" do
      it "creates a PrepGuide with all fields populated" do
        PrepGuideJob.perform_now(prep_session.id)
        guide = prep_session.reload.prep_guide
        expect(guide).to be_present
        expect(guide.likely_questions).to be_present
        expect(guide.star_outlines).to be_present
        expect(guide.questions_to_ask).to be_present
        expect(guide.watch_out).to be_present
        expect(guide.company_signals).to be_present
        expect(guide.gemini_raw).to be_present
      end

      it "sets PrepSession status to 'complete'" do
        PrepGuideJob.perform_now(prep_session.id)
        expect(prep_session.reload.status).to eq("complete")
      end

      it "stores sources as a valid JSON array on PrepGuide" do
        PrepGuideJob.perform_now(prep_session.id)
        # sources are collected via tool closures; stubbing GeminiService means no tools run,
        # so the array is empty — but it must be a parseable JSON array.
        sources = JSON.parse(prep_session.reload.prep_guide.sources)
        expect(sources).to be_an(Array)
      end

      it "stores agent_trace as a valid JSON array on PrepGuide" do
        PrepGuideJob.perform_now(prep_session.id)
        # agent_trace is populated via tool closures; stubbing GeminiService means no tools run.
        trace = JSON.parse(prep_session.reload.prep_guide.agent_trace)
        expect(trace).to be_an(Array)
      end
    end

    context "when GeminiService raises GeminiError" do
      before do
        allow(GeminiService).to receive(:generate_with_tools)
          .and_raise(GeminiService::GeminiError, "API quota exceeded")
      end

      it "sets PrepSession status to 'failed'" do
        PrepGuideJob.perform_now(prep_session.id)
        expect(prep_session.reload.status).to eq("failed")
      end

      it "sets error_message on PrepSession" do
        PrepGuideJob.perform_now(prep_session.id)
        expect(prep_session.reload.error_message).to eq("API quota exceeded")
      end

      it "does not create a PrepGuide" do
        PrepGuideJob.perform_now(prep_session.id)
        expect(prep_session.reload.prep_guide).to be_nil
      end
    end

    context "when GeminiService returns unparseable JSON" do
      before do
        allow(GeminiService).to receive(:generate_with_tools)
          .and_return({ text: "not valid json at all", sources: [], agent_trace: [] })
      end

      it "sets PrepSession status to 'failed'" do
        PrepGuideJob.perform_now(prep_session.id)
        expect(prep_session.reload.status).to eq("failed")
      end

      it "sets error_message mentioning parse failure" do
        PrepGuideJob.perform_now(prep_session.id)
        expect(prep_session.reload.error_message).to match(/parse/i)
      end
    end

    context "when the job description is present" do
      let(:prep_session) { create(:prep_session, user: user, job_description: "Looking for a Rails engineer.") }

      it "includes job description in the variables passed to GeminiService" do
        PrepGuideJob.perform_now(prep_session.id)
        expect(GeminiService).to have_received(:generate_with_tools) do |**kwargs|
          expect(kwargs[:variables][:job_description]).to include("Looking for a Rails engineer.")
        end
      end
    end
  end
end
