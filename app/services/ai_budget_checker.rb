class AiBudgetChecker
  def self.check!(user)
    new(user).check!
  end

  def initialize(user)
    @user  = user
    @limit = ENV.fetch("AI_CALLS_PER_USER_PER_DAY", "50").to_i
  end

  def check!
    count = LlmRequest.where(user: @user).today.count
    if count >= @limit
      raise GeminiService::BudgetExceededError,
            "Daily AI call limit of #{@limit} reached. Try again tomorrow."
    end
    true
  end

  def remaining_calls
    used = LlmRequest.where(user: @user).today.count
    [@limit - used, 0].max
  end
end
