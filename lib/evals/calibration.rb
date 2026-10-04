module Evals
  # Checks the LLM judge against human-labeled examples in
  # evals/judge_calibration.yml before its scores are trusted. A judge that
  # cannot tell a labeled pass from a labeled fail fails the run.
  class Calibration
    PATH       = Rails.root.join("evals/judge_calibration.yml")
    PASS_SCORE = 4

    def initialize(judge:)
      @judge = judge
    end

    def run
      return [] unless File.exist?(PATH)

      YAML.load_file(PATH).fetch("examples", []).map do |ex|
        verdict = @judge.score(criterion: ex["criterion"], input: ex["input"], output: ex["output"])
        judged  = verdict.score >= PASS_SCORE ? "pass" : "fail"
        { id: ex["id"], human: ex["label"], judge: judged, score: verdict.score, agree: judged == ex["label"] }
      end
    end
  end
end
