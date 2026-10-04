module Evals
  # One evals/cases/<template>.yml file: the Reference dataset for one AiTemplate.
  class CaseFile
    DIR = Rails.root.join("evals/cases")

    attr_reader :template, :rubric, :cases, :adapter_name

    def self.all(only: nil)
      Dir[DIR.join("*.yml")].sort.map { |path| new(path) }.select { |f| only.blank? || f.template == only }
    end

    def initialize(path)
      data          = YAML.load_file(path, aliases: true)
      @template     = data.fetch("template")
      @adapter_name = data["adapter"]
      @rubric       = Array(data["rubric"])
      @cases        = Array(data["cases"]).map { |c| c.merge("variables" => (c["variables"] || {}).transform_keys(&:to_s)) }
    end

    def adapter
      klass = @adapter_name ? @adapter_name.constantize : Adapters::Template
      klass.new(@template)
    end

    # The prompt AiGatekeeper sees for a case: the template rendered with the
    # case variables, or the bare variables when the template is not seeded.
    def rendered_prompt(kase)
      ai_template = AiTemplate.find_by(name: @template)
      return ai_template.interpolate(kase["variables"]) if ai_template
      kase["variables"].values.join("\n")
    end

    def self.blocking?(kase)
      %w[blocked crisis].include?(kase["expect"])
    end
  end
end
