# Scrubs credentials out of any text the app stores or prints: LlmRequest error messages,
# eval errors, and eval reports. Gemini keys are sent in the x-goog-api-key header (never
# the URL), so this is the second line of defence for anything an API or HTTP error echoes.
module SecretRedactor
  MASK = "[REDACTED]".freeze

  # ENV variables whose values are credentials, matched by name.
  SECRET_ENV_NAME = /(API_KEY|_TOKEN|_SECRET|PASSWORD)\z/

  # Credential shapes worth catching even if the value never came from ENV.
  PATTERNS = [
    /AIza[0-9A-Za-z_\-]{30,}/,                 # Google API key
    /([?&]key=)[^&\s"']+/,                     # key in a query string
    /(x-goog-api-key["']?\s*[:=>]+\s*["']?)[^"'\s,}]+/i,
    /(Bearer\s+)[A-Za-z0-9._\-]{8,}/          # Authorization header
  ].freeze

  module_function

  def redact(text)
    return text if text.blank?

    out = text.to_s.dup
    secret_values.each { |value| out.gsub!(value, MASK) }
    PATTERNS.each { |re| out.gsub!(re) { "#{Regexp.last_match(1)}#{MASK}" } }
    out
  end

  def secret_values
    ENV.select { |name, value| name.match?(SECRET_ENV_NAME) && value.to_s.length >= 8 }
       .values.sort_by { |v| -v.length }
  end
end
