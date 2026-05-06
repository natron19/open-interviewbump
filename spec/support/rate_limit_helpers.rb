module RateLimitHelpers
  # Prevent rate limit cascade failures in request specs by resetting the
  # Rails cache between examples. The cache store is cleared in rails_helper
  # after each example, so sign-in rate limits don't bleed across tests.
end

RSpec.configure do |config|
  config.include RateLimitHelpers
end
