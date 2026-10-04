module Evals
  # GRAFTS layer G. Runs AiGatekeeper and AiOutputGuard offline (no API calls)
  # against evals/guardrails.yml plus every case file, and measures catch rate
  # on attacks and false-positive rate on benign inputs, per guard.
  class GuardrailSuite
    PATH = Rails.root.join("evals/guardrails.yml")

    Row = Struct.new(:guard, :id, :attack, :blocked, :expected_crisis, :crisis, :detail, keyword_init: true) do
      def correct?
        attack ? blocked && (!expected_crisis || crisis) : !blocked
      end
    end

    def run
      data = File.exist?(PATH) ? YAML.load_file(PATH) : {}
      input_rows(data["input"] || {}) + case_file_rows + output_rows(data["output"] || {})
    end

    private

    def input_rows(section)
      Array(section["attacks"]).map { |a| gate("input", a["id"], text_for(a), attack: true, expect: a["expect"]) } +
        Array(section["benign"]).map { |b| gate("input", b["id"], text_for(b), attack: false) }
    end

    def text_for(item)
      item["text"].to_s * item.fetch("repeat", 1)
    end

    # Golden, edge and benign cases must pass the gate; expect: blocked/crisis cases must not.
    def case_file_rows
      CaseFile.all.flat_map do |file|
        file.cases.map do |kase|
          gate("input", "#{file.template}/#{kase['id']}", file.rendered_prompt(kase),
               attack: CaseFile.blocking?(kase), expect: kase["expect"])
        end
      end
    end

    def output_rows(section)
      Array(section["attacks"]).map { |a| output_guard(a, attack: true) } +
        Array(section["benign"]).map { |b| output_guard(b, attack: false) }
    end

    def gate(guard, id, text, attack:, expect: nil)
      AiGatekeeper.check!(text)
      Row.new(guard:, id:, attack:, blocked: false, expected_crisis: expect == "crisis", crisis: false, detail: "allowed")
    rescue GeminiService::GatekeeperError => e
      Row.new(guard:, id:, attack:, blocked: true, expected_crisis: expect == "crisis",
              crisis: e.is_a?(GeminiService::CrisisError), detail: e.message.truncate(80))
    end

    def output_guard(item, attack:)
      template = AiTemplate.find_by(name: item["template"]) ||
                 AiTemplate.new(name: item["template"].to_s, system_prompt: "You are a helpful assistant for this demo app. Follow the format exactly.")
      text = item["text"].to_s.gsub("{{system_prompt}}", template.system_prompt.to_s)
      AiOutputGuard.check!(text, template:, input: item["input"].to_s)
      Row.new(guard: "output", id: item["id"], attack:, blocked: false, detail: "allowed")
    rescue GeminiService::OutputGuardError => e
      Row.new(guard: "output", id: item["id"], attack:, blocked: true, detail: e.message.truncate(80))
    end
  end
end
