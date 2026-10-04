module Evals
  # Rolls results up by GRAFTS layer, ASSURED dimension and segment, applies the
  # decision bars from evals/bars.yml, and writes tmp/evals/report-<ts>.json.
  class Report
    BARS_PATH       = Rails.root.join("evals/bars.yml")
    JUDGE_PASS      = 4
    ASSURED         = %w[accurate safe steerable useful reliable efficient durable].freeze

    # [metric, bar key, :min or :max]
    BAR_RULES = [
      [:guard_catch_rate,          "guard_catch_rate",          :min],
      [:guard_false_positive_rate, "guard_false_positive_rate", :max],
      [:deterministic_pass_rate,   "deterministic_pass_rate",   :min],
      [:judge_mean_score,          "judge_mean_score",          :min],
      [:judge_min_score,           "judge_min_score",           :min],
      [:judge_agreement,           "judge_agreement",           :min],
      [:p95_latency_ms,            "p95_latency_ms",            :max],
      [:error_rate,                "error_rate",                :max],
    ].freeze

    def initialize(guardrails:, cases: [], calibration: [])
      @guardrails  = guardrails
      @cases       = cases
      @calibration = calibration
      @bars        = YAML.load_file(BARS_PATH)
    end

    def metrics
      @metrics ||= guard_metrics.merge(text_metrics).merge(system_metrics).merge(judge_agreement: agreement)
    end

    def bar_results
      BAR_RULES.filter_map do |metric, key, direction|
        value = metrics[metric]
        next if value.nil? || !@bars.key?(key)
        bar = @bars[key]
        { metric:, value:, bar:, direction:, passed: direction == :min ? value >= bar : value <= bar }
      end
    end

    def passed?
      bar_results.all? { |r| r[:passed] }
    end

    def print(io = $stdout)
      io.puts "\n== GRAFTS: Guardrails (G) =="
      %w[input output].each do |guard|
        rows = @guardrails.select { |r| r.guard == guard }
        next if rows.empty?
        io.puts format("  %-7s attacks blocked %d/%d   benign allowed %d/%d", guard,
                       rows.count { |r| r.attack && r.correct? }, rows.count(&:attack),
                       rows.count { |r| !r.attack && r.correct? }, rows.count { |r| !r.attack })
        rows.reject(&:correct?).each { |r| io.puts "    MISS #{r.attack ? 'attack' : 'benign'} #{r.id}: #{r.detail}" }
      end

      if @cases.any?
        io.puts "\n== GRAFTS: Text generation (T), Agent (A), Function calls (F) =="
        @cases.each do |c|
          next io.puts("  #{c[:template]}/#{c[:id]}  ERROR #{c[:error]}") if c[:error]
          failed = c[:checks].reject { |k| k[:passed] }
          scores = c[:judgments].map { |j| j[:score] }.join(",")
          io.puts format("  %-48s checks %d/%d  judge [%s]", "#{c[:template]}/#{c[:id]}",
                         c[:checks].size - failed.size, c[:checks].size, scores)
          failed.each { |k| io.puts "      FAIL #{k[:layer]} #{k[:type]}: #{k[:detail]}" }
          c[:judgments].select { |j| j[:score] < JUDGE_PASS }.each { |j| io.puts "      LOW  #{j[:dimension]} #{j[:score]}: #{j[:reason].to_s.truncate(120)}" }
        end

        io.puts "\n== GRAFTS: System (S) =="
        io.puts format("  latency p50 %s ms  p95 %s ms   avg cost %.4f cents   error rate %.0f%%",
                       metrics[:p50_latency_ms] || "n/a", metrics[:p95_latency_ms] || "n/a",
                       metrics[:avg_cost_cents], metrics[:error_rate] * 100)

        io.puts "\n== ASSURED dimensions =="
        assured_rollup.each { |dim, (ok, total)| io.puts format("  %-10s %d/%d", dim, ok, total) }

        io.puts "\n== Segments =="
        segment_rollup.each { |seg, (ok, total)| io.puts format("  %-16s %d/%d", seg, ok, total) }
      end

      if @calibration.any?
        io.puts "\n== Judge calibration (human labels) =="
        @calibration.reject { |c| c[:agree] }.each { |c| io.puts "  DISAGREE #{c[:id]}: human #{c[:human]}, judge #{c[:judge]} (#{c[:score]})" }
        io.puts format("  agreement %d/%d", @calibration.count { |c| c[:agree] }, @calibration.size)
      end

      io.puts "\n== Decision bars =="
      bar_results.each do |r|
        io.puts format("  %-4s %-26s %8s  (%s %s)", r[:passed] ? "PASS" : "FAIL", r[:metric], fmt(r[:value]),
                       r[:direction] == :min ? ">=" : "<=", r[:bar])
      end
      io.puts passed? ? "\nRESULT: PASS" : "\nRESULT: FAIL"
    end

    def write_json
      dir = Rails.root.join("tmp/evals")
      FileUtils.mkdir_p(dir)
      path = dir.join("report-#{Time.current.strftime('%Y%m%d-%H%M%S')}.json")
      File.write(path, JSON.pretty_generate(
        metrics:, bars: bar_results, passed: passed?, assured: assured_rollup, segments: segment_rollup,
        guardrails: @guardrails.map(&:to_h), cases: @cases, calibration: @calibration
      ))
      path
    end

    private

    def guard_metrics
      attacks = @guardrails.select(&:attack)
      benign  = @guardrails.reject(&:attack)
      { guard_catch_rate:          rate(attacks.count(&:correct?), attacks.size),
        guard_false_positive_rate: rate(benign.count { |r| !r.correct? }, benign.size) }
    end

    def text_metrics
      return {} if @cases.empty?
      checks = @cases.flat_map { |c| c[:checks] }
      scores = @cases.flat_map { |c| c[:judgments].map { |j| j[:score] } }
      { deterministic_pass_rate: rate(checks.count { |k| k[:passed] }, checks.size),
        judge_mean_score:        scores.any? ? (scores.sum.to_f / scores.size).round(2) : nil,
        judge_min_score:         scores.min }
    end

    def system_metrics
      return {} if @cases.empty?
      latencies = @cases.reject { |c| c[:error] }.map { |c| c[:duration_ms] }.sort
      { p50_latency_ms: percentile(latencies, 50),
        p95_latency_ms: percentile(latencies, 95),
        avg_cost_cents: (@cases.sum { |c| c[:cost_cents] } / @cases.size).round(4),
        error_rate:     rate(@cases.count { |c| c[:error] }, @cases.size) }
    end

    def agreement
      rate(@calibration.count { |c| c[:agree] }, @calibration.size) if @calibration.any?
    end

    def assured_rollup
      items = @cases.flat_map do |c|
        c[:checks].map { |k| [k[:dimension], k[:passed]] } + c[:judgments].map { |j| [j[:dimension], j[:score] >= JUDGE_PASS] }
      end
      ASSURED.index_with { |dim| tally(items.select { |d, _| d == dim }) }.reject { |_, (_, total)| total.zero? }
    end

    # A case passes when every check passes and every judge score clears JUDGE_PASS.
    def segment_rollup
      @cases.group_by { |c| c[:segment] }.transform_values do |cs|
        [cs.count { |c| !c[:error] && c[:checks].all? { |k| k[:passed] } && c[:judgments].all? { |j| j[:score] >= JUDGE_PASS } }, cs.size]
      end
    end

    def tally(pairs)
      [pairs.count { |_, ok| ok }, pairs.size]
    end

    def rate(numerator, denominator)
      denominator.zero? ? nil : (numerator.to_f / denominator).round(3)
    end

    def percentile(sorted, pct)
      return nil if sorted.empty?
      sorted[((pct / 100.0) * (sorted.size - 1)).round]
    end

    def fmt(value)
      value.is_a?(Float) ? format("%.3g", value) : value.to_s
    end
  end
end
