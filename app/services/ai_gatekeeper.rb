class AiGatekeeper
  MAX_INPUT_LENGTH = 50_000

  INJECTION_PATTERNS = [
    /ignore\s+(all\s+)?previous\s+instructions/i,
    /disregard\s+(all\s+)?previous/i,
    /you\s+are\s+now\s+in\s+developer\s+mode/i,
    /jailbreak/i,
    /pretend\s+you\s+(are|have\s+no)/i,
    /system\s*:\s*you\s+are/i,
  ].freeze

  BLOCKED_TERMS = %w[
    fuck shit asshole cunt bitch
  ].freeze

  def self.check!(input, user = nil)
    new(input, user).check!
  end

  def initialize(input, user = nil)
    @input = input.to_s
    @user  = user
  end

  def check!
    raise_gatekeeper("Input too long (max #{MAX_INPUT_LENGTH} characters).") if too_long?
    raise_gatekeeper("Potential prompt injection detected.")                  if injection_attempt?
    raise_gatekeeper("Input contains blocked content.")                       if contains_profanity?
    true
  end

  private

  def too_long?
    @input.length > MAX_INPUT_LENGTH
  end

  def injection_attempt?
    INJECTION_PATTERNS.any? { |pattern| @input.match?(pattern) }
  end

  def contains_profanity?
    downcased = @input.downcase
    BLOCKED_TERMS.any? { |term| downcased.include?(term) }
  end

  def raise_gatekeeper(message)
    raise GeminiService::GatekeeperError, message
  end
end
