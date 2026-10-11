module Evals
  # Live run (GRAFTS layers T, S, and A/F for agent adapters). Calls Gemini for
  # every case that is expected to get an answer, applies the deterministic
  # checks, then asks the LLM judge to score each rubric criterion.
  class Runner
    EVAL_USER_EMAIL = "evals@example.com".freeze

    LAYER_BY_CHECK = {
      "tools_subset_of"  => "F",
      "called_tool"      => "F",
      "max_tool_calls"   => "A",
      "latency_under_ms" => "S",
    }.freeze

    def self.eval_user
      User.find_or_create_by!(email: EVAL_USER_EMAIL) do |u|
        u.name     = "Eval Harness"
        u.password = SecureRandom.hex(16)
      end
    end

    # A case's criteria add to the file's rubric. One marked `replaces: true` stands in for the
    # file's criterion of the same dimension, for a case where the general one can't apply
    # (e.g. the right answer deliberately changes what the input asked for).
    def self.rubric_for(file_rubric, case_rubric)
      case_rubric = Array(case_rubric)
      replaced    = case_rubric.select { |item| item["replaces"] }.map { |item| item["dimension"] }
      Array(file_rubric).reject { |item| replaced.include?(item["dimension"]) } + case_rubric
    end

    def initialize(only: nil, user: self.class.eval_user, judge: nil, io: $stdout)
      @only  = only
      @user  = user
      @judge = judge || Judge.new(user: user)
      @io    = io
    end

    def run
      CaseFile.all(only: @only).flat_map do |file|
        adapter = file.adapter
        file.cases.reject { |c| CaseFile.blocking?(c) }.map do |kase|
          @io.print "  #{file.template}/#{kase['id']} ... "
          run_case(file, adapter, kase).tap { |r| @io.puts(r[:error] ? "error" : "done") }
        end
      end
    end

    private

    def run_case(file, adapter, kase)
      started = Time.current
      result  = { template: file.template, id: kase["id"], kind: kase["kind"], segment: kase["segment"] || "general",
                  checks: [], judgments: [] }

      begin
        outcome = adapter.call(variables: kase["variables"], user: @user)
      rescue GeminiService::GeminiError => e
        result[:error] = SecretRedactor.redact("#{e.class.name.demodulize}: #{e.message}")
      end
      result.merge!(system_metrics(file.template, started))
      return result if result[:error]

      context = Checks::Context.new(output: outcome.output, variables: kase["variables"],
                                    trace: Array(outcome.trace), duration_ms: result[:duration_ms])
      result[:output_preview] = outcome.output.to_s.truncate(300)
      result[:checks]    = Array(kase["checks"]).map { |check| grade(check, context) }
      result[:judgments] = self.class.rubric_for(file.rubric, kase["rubric"]).map { |item| judge(item, kase, outcome.output) }
      result
    end

    def grade(check, context)
      passed, detail = Checks.run(check, context)
      { type: check["type"], dimension: check["dimension"] || "steerable",
        layer: LAYER_BY_CHECK.fetch(check["type"].to_s, "T"), passed: passed, detail: detail }
    end

    def judge(item, kase, output)
      input   = kase["variables"].map { |k, v| "#{k}: #{v}" }.join("\n")
      verdict = @judge.score(criterion: item.fetch("criterion"), input: input, output: output)
      { dimension: item["dimension"] || "useful", criterion: item["criterion"], score: verdict.score, reason: verdict.reason }
    end

    # Every GeminiService call already writes an LlmRequest row; S-layer metrics
    # are read back from the rows this case created.
    def system_metrics(template, started)
      logs = LlmRequest.where(user: @user, template_name: template).where("created_at >= ?", started)
      { duration_ms: logs.sum(:duration_ms).to_i, cost_cents: logs.sum(:cost_estimate_cents).to_f, calls: logs.count }
    end
  end
end
