require "rails_helper"

RSpec.describe Evals::Judge do
  let(:user)  { create(:user) }
  let(:judge) { Evals::Judge.new(user: user) }

  it "parses the judge's JSON verdict" do
    allow(GeminiService).to receive(:generate).and_return("```json\n{\"score\": 5, \"reason\": \"Fully grounded.\"}\n```")

    verdict = judge.score(criterion: "Grounded", input: "a", output: "b")

    expect(verdict.score).to eq(5)
    expect(verdict.reason).to eq("Fully grounded.")
  end

  it "calls GeminiService as a trusted caller so long outputs skip the input gatekeeper" do
    allow(GeminiService).to receive(:generate).and_return('{"score": 3, "reason": "Partial."}')

    judge.score(criterion: "c", input: "i", output: "o" * 6000)

    expect(GeminiService).to have_received(:generate)
      .with(hash_including(template: "eval_judge_v1", trusted: true, user: user))
  end

  it "scores 0 when the verdict is unparseable or the call fails" do
    allow(GeminiService).to receive(:generate).and_return("I think it is good")
    expect(judge.score(criterion: "c", input: "i", output: "o").score).to eq(0)

    allow(GeminiService).to receive(:generate).and_raise(GeminiService::TimeoutError, "slow")
    expect(judge.score(criterion: "c", input: "i", output: "o").reason).to match(/failed/)
  end

  it "tells the judge today's date so recent dates don't read as future ones" do
    allow(GeminiService).to receive(:generate).and_return('{"score": 5, "reason": "ok"}')

    allow(Date).to receive(:current).and_return(Date.new(2026, 10, 10))
    judge.score(criterion: "Dates are plausible", input: "i", output: "o")

    expect(GeminiService).to have_received(:generate).with(hash_including(
      variables: hash_including(criterion: a_string_including("Dates are plausible", "Today's date is 2026-10-10"))
    ))
  end
end
