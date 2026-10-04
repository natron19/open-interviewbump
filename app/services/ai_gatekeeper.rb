class AiGatekeeper
  MAX_INPUT_LENGTH = 50_000

  INJECTION_PATTERNS = [
    /ignore\s+(all\s+)?previous\s+instructions/i,
    /disregard\s+(all\s+)?previous/i,
    /you\s+are\s+now\s+in\s+developer\s+mode/i,
    /jailbreak/i,
    /pretend\s+you\s+(are|have\s+no)/i,
    /system\s*:\s*you\s+are/i,
    /(reveal|show|print|repeat)\s+(me\s+)?(your\s+(system\s+)?|the\s+system\s+)(prompt|instructions)/i,
    /<\s*\/?\s*system\s*>|\[\s*system\s*\]/i,
  ].freeze

  CRISIS_MESSAGE = "It sounds like you may be going through something really hard. " \
                   "This demo can't help with that, but people can: in the US, call or text 988 " \
                   "(Suicide & Crisis Lifeline), or contact local emergency services.".freeze

  INJECTION_REDACTION = "[removed: possible prompt injection]".freeze

  BLOCKED_TERMS = %w[
    fuck shit asshole cunt bitch
  ].freeze

  def self.check!(input, user = nil)
    new(input, user).check!
  end

  # Neutralizes injection attempts in untrusted third-party text (fetched pages,
  # search results) before it is handed back to the model.
  def self.scan_untrusted(text)
    INJECTION_PATTERNS.reduce(text.to_s) { |clean, pattern| clean.gsub(pattern, INJECTION_REDACTION) }
  end

  def initialize(input, user = nil)
    @input = input.to_s
    @user  = user
  end

  def check!
    raise_gatekeeper("Input too long (max #{MAX_INPUT_LENGTH} characters).") if too_long?
    raise GeminiService::CrisisError, CRISIS_MESSAGE                          if crisis_signal?
    raise_gatekeeper("Potential prompt injection detected.")                  if injection_attempt?
    raise_gatekeeper("Input contains blocked content.")                       if contains_profanity?
    true
  end

  private

  def too_long?
    @input.length > MAX_INPUT_LENGTH
  end

  def crisis_signal?
    downcased = @input.downcase
    AiGuardConfig.crisis_terms.any? { |term| downcased.include?(term) }
  end

  def injection_attempt?
    INJECTION_PATTERNS.any? { |pattern| @input.match?(pattern) }
  end

  # Word-prefix match: catches "fucking" but not "Scunthorpe".
  def contains_profanity?
    BLOCKED_TERMS.any? { |term| @input.match?(/\b#{Regexp.escape(term)}/i) }
  end

  def raise_gatekeeper(message)
    raise GeminiService::GatekeeperError, message
  end
end
