class AiOutputGuard
  LEAK_PREFIX_LENGTH = 80

  PII_PATTERNS = {
    "SSN"                => /\b\d{3}-\d{2}-\d{4}\b/,
    "credit card number" => /\b(?:\d[ -]?){12,18}\d\b/,
    "email address"      => /\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b/,
    "phone number"       => /(?<!\d)(?:\+?1[-. ]?)?\(?\d{3}\)?[-. ]\d{3}[-. ]\d{4}(?!\d)/,
  }.freeze

  PLACEHOLDER_EMAIL_DOMAINS = /@(example\.(com|org|net)|yourcompany\.com|company\.com)\z/i

  # Toll-free numbers belong to organizations (e.g. crisis hotlines), not people.
  TOLL_FREE_PHONE = /\A(?:\+?1[-. ]?)?\(?8(00|33|44|55|66|77|88)\)?[-. ]/

  def self.check!(output, template:, input: "")
    new(output, template:, input:).check!
  end

  # Pulls the JSON payload out of a model response, tolerating ```json fences
  # and leading/trailing prose. Returns nil when nothing parses.
  def self.extract_json(text)
    body  = text.to_s.gsub(/```(?:json)?/i, "")
    start = body.index(/[\[{]/)
    return nil unless start

    closer = body[start] == "{" ? "}" : "]"
    stop   = body.rindex(closer)
    return nil unless stop && stop > start

    JSON.parse(body[start..stop])
  rescue JSON::ParserError
    nil
  end

  # Gemini sometimes writes raw line breaks or tabs inside JSON strings, which JSON.parse
  # rejects. For templates whose guard rules say format: json, escape them, but only when
  # that turns unparseable text into parseable text. Anything else comes back unchanged.
  def self.repair_json_text(text, template_name)
    return text unless AiGuardConfig.for_template(template_name)[:format] == "json"
    return text if extract_json(text)

    repaired = escape_control_chars_in_strings(text.to_s)
    extract_json(repaired) ? repaired : text
  end

  def self.escape_control_chars_in_strings(text)
    in_string = false
    escaped   = false
    text.each_char.map do |c|
      if !in_string
        in_string = true if c == '"'
        c
      elsif escaped
        escaped = false
        c
      elsif c == "\\"
        escaped = true
        c
      elsif c == '"'
        in_string = false
        c
      elsif c.ord < 0x20
        format("\\u%04x", c.ord)
      else
        c
      end
    end.join
  end

  def initialize(output, template:, input: "")
    @output   = output.to_s
    @template = template
    @input    = input.to_s
    @rules    = AiGuardConfig.for_template(template.name)
  end

  def check!
    raise_guard("Empty response.")                          if @output.strip.empty?
    raise_guard("Response repeated the system prompt.")     if leaks_system_prompt?
    raise_guard("Response contained blocked content.")      if contains_profanity?
    raise_guard("Response contained a #{new_pii}.")         if new_pii
    check_structure!
    true
  end

  private

  def leaks_system_prompt?
    prefix = normalize(@template.system_prompt)[0, LEAK_PREFIX_LENGTH]
    prefix.length >= 40 && normalize(@output).include?(prefix)
  end

  def contains_profanity?
    AiGatekeeper::BLOCKED_TERMS.any? { |term| @output.match?(/\b#{Regexp.escape(term)}/i) }
  end

  # PII the model introduced on its own. Anything the user supplied is allowed back.
  def new_pii
    return @new_pii if defined?(@new_pii)

    @new_pii = PII_PATTERNS.find do |label, pattern|
      @output.scan(pattern).any? do |match|
        next false if @input.include?(match)
        next false if label == "email address" && match.match?(PLACEHOLDER_EMAIL_DOMAINS)
        next false if label == "credit card number" && !luhn_valid?(match)
        next false if label == "phone number" && match.match?(TOLL_FREE_PHONE)
        true
      end
    end&.first
  end

  def check_structure!
    return unless @rules[:format] == "json"

    parsed = self.class.extract_json(@output)
    raise_guard("Response was not valid JSON.") if parsed.nil?

    missing = Array(@rules[:required_keys]).map(&:to_s) - (parsed.is_a?(Hash) ? parsed.keys : [])
    raise_guard("Response JSON was missing: #{missing.join(', ')}.") if missing.any?
  end

  def luhn_valid?(number)
    digits = number.gsub(/\D/, "").reverse.chars.map(&:to_i)
    sum = digits.each_with_index.sum { |d, i| i.odd? ? (d * 2).digits.sum : d }
    (sum % 10).zero?
  end

  def normalize(text)
    text.to_s.downcase.gsub(/\s+/, " ").strip
  end

  def raise_guard(message)
    raise GeminiService::OutputGuardError, message
  end
end
