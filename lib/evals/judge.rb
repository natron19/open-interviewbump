module Evals
  # LLM-as-judge. Scores one rubric criterion at a time on a 1-5 scale using the
  # seeded eval_judge_v1 template. Runs through GeminiService (trusted: true) so
  # every judge call is still logged and time-bounded.
  class Judge
    TEMPLATE = "eval_judge_v1".freeze

    Verdict = Struct.new(:score, :reason, keyword_init: true)

    def initialize(user:)
      @user = user
    end

    def score(criterion:, input:, output:)
      raw  = GeminiService.generate(
        template:  TEMPLATE,
        variables: { criterion: criterion, input: input, output: output },
        user:      @user,
        trusted:   true
      )
      json = AiOutputGuard.extract_json(raw) || {}
      Verdict.new(score: json["score"].to_i.clamp(0, 5), reason: json["reason"].to_s.presence || raw.to_s.truncate(200))
    rescue GeminiService::GeminiError => e
      Verdict.new(score: 0, reason: "Judge call failed: #{e.message}")
    end
  end
end
