namespace :evals do
  desc "Guardrail evals (GRAFTS: G). Offline, no API calls, no cost."
  task guardrails: :environment do
    report = Evals::Report.new(guardrails: Evals::GuardrailSuite.new.run)
    report.print
    puts "Report: #{report.write_json}"
    exit(1) unless report.passed?
  end

  desc "Full eval run (GRAFTS: G, T, S, plus A/F for agent apps) against live Gemini. Optional: evals:run[template_name]"
  task :run, [:template] => :environment do |_, args|
    abort "GEMINI_API_KEY is not set." if ENV["GEMINI_API_KEY"].blank?
    abort "eval_judge_v1 template missing. Run bin/rails db:seed." unless AiTemplate.exists?(name: Evals::Judge::TEMPLATE)

    # The per-user demo budget protects real users; the eval user is exempt.
    ENV["AI_CALLS_PER_USER_PER_DAY"] = "100000"

    user = Evals::Runner.eval_user
    judge = Evals::Judge.new(user: user)

    puts "Running cases#{" for #{args[:template]}" if args[:template]}:"
    cases = Evals::Runner.new(only: args[:template], user: user, judge: judge).run
    puts "Calibrating judge against human labels..."
    calibration = Evals::Calibration.new(judge: judge).run

    report = Evals::Report.new(guardrails: Evals::GuardrailSuite.new.run, cases: cases, calibration: calibration)
    report.print
    puts "Report: #{report.write_json}"
    exit(1) unless report.passed?
  end
end
