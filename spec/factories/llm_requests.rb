FactoryBot.define do
  factory :llm_request do
    user
    ai_template
    template_name        { ai_template&.name }
    status               { "success" }
    prompt_token_count   { 100 }
    response_token_count { 200 }
    duration_ms          { 450 }
    cost_estimate_cents  { 0.0012 }

    trait :error do
      status        { "error" }
      error_message { "Something went wrong" }
    end

    trait :timeout do
      status        { "timeout" }
      error_message { "Timed out after 15s" }
    end

    trait :gatekeeper_blocked do
      status { "gatekeeper_blocked" }
    end

    trait :budget_exceeded do
      status { "budget_exceeded" }
    end
  end
end
