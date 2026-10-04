module Evals
  # Deterministic graders (GRAFTS: Text generation, plus Agent/Function checks
  # that read the adapter trace). Each check returns [passed, detail].
  #
  # Paths are dot-separated keys into the parsed JSON ("phases" or "plan.weeks").
  # Values written as "{{var}}" are replaced with the case's input variables.
  module Checks
    Context = Struct.new(:output, :variables, :trace, :duration_ms, keyword_init: true) do
      def json
        return @json if defined?(@json)
        @json = AiOutputGuard.extract_json(output)
      end

      def at(path)
        return json if path.blank?
        path.to_s.split(".").reduce(json) do |node, key|
          case node
          when Hash  then node[key]
          when Array then key.match?(/\A\d+\z/) ? node[key.to_i] : nil
          end
        end
      end

      def interpolate(value)
        return value unless value.is_a?(String)
        value.gsub(/\{\{(\w+)\}\}/) { variables[Regexp.last_match(1)].to_s }
      end
    end

    module_function

    def run(check, context)
      type = check.fetch("type").to_s
      raise ArgumentError, "Unknown eval check: #{type}" unless NAMES.include?(type)
      send(type, check, context)
    rescue ArgumentError, KeyError, TypeError, NoMethodError => e
      [false, "#{type} errored: #{e.message}"]
    end

    def not_empty(_c, ctx)
      [ctx.output.to_s.strip.present?, "#{ctx.output.to_s.length} chars"]
    end

    def json_valid(_c, ctx)
      [!ctx.json.nil?, ctx.json.nil? ? "no parseable JSON" : "parsed"]
    end

    def has_keys(c, ctx)
      node    = ctx.at(c["path"])
      missing = Array(c["keys"]).map(&:to_s) - (node.is_a?(Hash) ? node.keys : [])
      [missing.empty?, missing.empty? ? "all present" : "missing #{missing.join(', ')}"]
    end

    def each_has_keys(c, ctx)
      items = Array(ctx.at(c["path"]))
      bad   = items.each_index.reject { |i| items[i].is_a?(Hash) && (Array(c["keys"]).map(&:to_s) - items[i].keys).empty? }
      [items.any? && bad.empty?, items.empty? ? "no items at #{c['path']}" : "#{bad.size}/#{items.size} items missing keys"]
    end

    def count_between(c, ctx)
      node  = ctx.at(c["path"])
      count = node.respond_to?(:size) && !node.is_a?(String) ? node.size : 0
      [count.between?(c.fetch("min", 0), c.fetch("max", Float::INFINITY)), "count #{count}, expected #{c['min']}..#{c['max']}"]
    end

    def max_chars(c, ctx)
      texts = c["path"] ? Array(ctx.at(c["path"])).map(&:to_s) : [ctx.output.to_s]
      worst = texts.map(&:length).max.to_i
      [texts.any? && worst <= c.fetch("value"), "longest #{worst}, max #{c['value']}"]
    end

    def max_words(c, ctx)
      words = ctx.output.to_s.split.size
      [words <= c.fetch("value"), "#{words} words, max #{c['value']}"]
    end

    def contains_all(c, ctx)
      haystack = ctx.output.to_s.downcase
      missing  = Array(c["values"]).map { |v| ctx.interpolate(v).to_s }.reject { |v| haystack.include?(v.downcase) }
      [missing.empty?, missing.empty? ? "all present" : "missing #{missing.join(', ')}"]
    end

    def not_contains(c, ctx)
      haystack = ctx.output.to_s.downcase
      found    = Array(c["values"]).map { |v| ctx.interpolate(v).to_s }.select { |v| haystack.include?(v.downcase) }
      [found.empty?, found.empty? ? "none found" : "found #{found.join(', ')}"]
    end

    def matches(c, ctx)
      pattern = Regexp.new(c.fetch("pattern"), Regexp::IGNORECASE)
      [ctx.output.to_s.match?(pattern), "/#{c['pattern']}/"]
    end

    def sum_equals(c, ctx)
      items    = Array(ctx.at(c["path"]))
      total    = items.sum { |i| i.is_a?(Hash) ? i[c.fetch("field")].to_s[/\d+(\.\d+)?/].to_f : 0 }
      expected = ctx.interpolate(c.fetch("value")).to_s[/\d+(\.\d+)?/].to_f
      [items.any? && (total - expected).abs <= c.fetch("tolerance", 0), "sum #{total}, expected #{expected}"]
    end

    def values_in(c, ctx)
      items   = Array(ctx.at(c["path"]))
      allowed = Array(c["allowed"]).map { |v| v.to_s.downcase }
      bad     = items.map { |i| i.is_a?(Hash) ? i[c.fetch("field")] : i }.reject { |v| allowed.include?(v.to_s.downcase) }
      [items.any? && bad.empty?, bad.empty? ? "all allowed" : "unexpected #{bad.uniq.join(', ')}"]
    end

    def sorted_desc(c, ctx)
      values = Array(ctx.at(c["path"])).map { |i| i.is_a?(Hash) ? i[c.fetch("field")].to_f : i.to_f }
      [values.any? && values == values.sort.reverse, values.join(", ")]
    end

    def latency_under_ms(c, ctx)
      [ctx.duration_ms.to_i < c.fetch("value"), "#{ctx.duration_ms} ms"]
    end

    # --- Agent trajectory / Function call checks (read the adapter trace) ---

    def tools_subset_of(c, ctx)
      used  = ctx.trace.map { |step| step[:tool].to_s }.uniq
      extra = used - Array(c["values"]).map(&:to_s)
      [extra.empty?, "used #{used.join(', ').presence || 'none'}"]
    end

    def max_tool_calls(c, ctx)
      [ctx.trace.size <= c.fetch("value"), "#{ctx.trace.size} calls, max #{c['value']}"]
    end

    def called_tool(c, ctx)
      [ctx.trace.any? { |step| step[:tool].to_s == c.fetch("value").to_s }, "expected #{c['value']}"]
    end

    NAMES = (singleton_methods - %i[run]).map(&:to_s).freeze
  end
end
