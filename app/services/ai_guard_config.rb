class AiGuardConfig
  PATH = Rails.root.join("config/ai_guards.yml")

  def self.crisis_terms
    Array(data["crisis_terms"]).map(&:downcase)
  end

  def self.for_template(name)
    (data.dig("templates", name.to_s) || {}).with_indifferent_access
  end

  def self.data
    @data = nil unless Rails.env.production?
    @data ||= File.exist?(PATH) ? YAML.load_file(PATH) || {} : {}
  end
end
