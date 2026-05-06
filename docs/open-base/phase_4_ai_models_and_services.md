# Phase 4 — AI Models & Services

**Goal:** Every Gemini call is logged, gated, budgeted, and time-bounded. The service is callable from any controller with a single line.

**Depends on:** Phase 2 complete (User model exists, `Current.user` available)

---

## 1. Migrations

### `CreateAiTemplates`

```ruby
create_table :ai_templates, id: :uuid do |t|
  t.string  :name,                 null: false
  t.string  :description
  t.text    :system_prompt,        null: false
  t.text    :user_prompt_template, null: false
  t.string  :model,                default: "gemini-2.0-flash", null: false
  t.integer :max_output_tokens,    default: 2000,               null: false
  t.decimal :temperature,          default: 0.7,  precision: 3, scale: 1
  t.text    :notes
  t.timestamps
end

add_index :ai_templates, :name, unique: true
```

### `CreateLlmRequests`

```ruby
create_table :llm_requests, id: :uuid do |t|
  t.references :user,           null: false, foreign_key: true, type: :uuid
  t.references :ai_template,    null: true,  foreign_key: true, type: :uuid
  t.string  :template_name
  t.string  :status,            null: false, default: "pending"
  t.integer :prompt_token_count
  t.integer :response_token_count
  t.integer :duration_ms
  t.decimal :cost_estimate_cents, precision: 10, scale: 4
  t.text    :error_message
  t.timestamps
end

add_index :llm_requests, :created_at
add_index :llm_requests, :status
```

---

## 2. Models

### `AiTemplate`

```ruby
class AiTemplate < ApplicationRecord
  validates :name,                 presence: true, uniqueness: true
  validates :system_prompt,        presence: true
  validates :user_prompt_template, presence: true
  validates :model,                presence: true
  validates :max_output_tokens,    presence: true, numericality: { greater_than: 0 }
  validates :temperature,          numericality: { greater_than_or_equal_to: 0.0,
                                                   less_than_or_equal_to: 2.0 }

  def variable_names
    user_prompt_template.scan(/\{\{(\w+)\}\}/).flatten.uniq
  end

  def interpolate(variables = {})
    result = user_prompt_template.dup
    variables.each do |key, value|
      result.gsub!("{{#{key}}}", value.to_s)
    end
    result
  end
end
```

### `LlmRequest`

```ruby
class LlmRequest < ApplicationRecord
  belongs_to :user
  belongs_to :ai_template, optional: true

  STATUSES = %w[pending success error timeout gatekeeper_blocked budget_exceeded].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :today,      -> { where(created_at: Date.current.all_day) }
  scope :this_week,  -> { where(created_at: 1.week.ago..Time.current) }
  scope :successful, -> { where(status: "success") }
  scope :failed,     -> { where(status: %w[error timeout gatekeeper_blocked budget_exceeded]) }
  scope :recent,     -> { order(created_at: :desc).limit(100) }
end
```

---

## 3. Services

### `AiGatekeeper`

`app/services/ai_gatekeeper.rb`

Checks the rendered user prompt before any API call.

```ruby
class AiGatekeeper
  MAX_INPUT_LENGTH = 5000

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
```

### `AiBudgetChecker`

`app/services/ai_budget_checker.rb`

```ruby
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
    used  = LlmRequest.where(user: @user).today.count
    [@limit - used, 0].max
  end
end
```

### `GeminiService`

`app/services/gemini_service.rb`

Full 9-step flow:

```ruby
require "google/apis/generativelanguage_v1beta"

class GeminiService
  class GeminiError        < StandardError; end
  class GatekeeperError    < GeminiError;   end
  class BudgetExceededError < GeminiError;  end
  class TimeoutError       < GeminiError;   end

  TIMEOUT_SECONDS = ENV.fetch("AI_GLOBAL_TIMEOUT_SECONDS", "15").to_i

  def self.generate(template:, variables: {}, user: Current.user)
    new(template:, variables:, user:).generate
  end

  def initialize(template:, variables: {}, user:)
    @template_name = template
    @variables     = variables
    @user          = user
  end

  def generate
    # Step 1 — template lookup
    ai_template = AiTemplate.find_by!(name: @template_name)

    # Step 2 — interpolate prompt
    rendered_prompt = ai_template.interpolate(@variables)

    # Step 3 — gatekeeper
    AiGatekeeper.check!(rendered_prompt, @user)

    # Step 4 — budget check
    AiBudgetChecker.check!(@user)

    # Step 5 — open log record
    log = LlmRequest.create!(
      user:          @user,
      ai_template:   ai_template,
      template_name: ai_template.name,
      status:        "pending"
    )

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      response_text = call_gemini(ai_template, rendered_prompt)
      duration_ms   = elapsed_ms(start_time)

      log.update!(
        status:               "success",
        prompt_token_count:   estimate_tokens(rendered_prompt),
        response_token_count: estimate_tokens(response_text),
        duration_ms:          duration_ms,
        cost_estimate_cents:  estimate_cost(rendered_prompt, response_text, ai_template.model)
      )

      response_text

    rescue Timeout::Error
      log.update!(status: "timeout", duration_ms: elapsed_ms(start_time),
                  error_message: "Gemini call timed out after #{TIMEOUT_SECONDS}s")
      raise TimeoutError, "The AI request timed out. Please try again."

    rescue => e
      log.update!(status: "error", duration_ms: elapsed_ms(start_time),
                  error_message: e.message.truncate(500))
      raise GeminiError, "An error occurred while generating a response."
    end
  end

  private

  def call_gemini(ai_template, rendered_prompt)
    client = Google::Cloud::AIPlatform.new  # actual gem interface TBD by gem version
    # Use the google-generative-ai gem's API:
    # Timeout enforced via Timeout.timeout(TIMEOUT_SECONDS)
    Timeout.timeout(TIMEOUT_SECONDS) do
      # implementation varies by gem version; skeleton only
      # returns the response text string
    end
  end

  def estimate_tokens(text)
    (text.length / 4.0).ceil
  end

  def estimate_cost(prompt, response, model)
    # gemini-2.0-flash pricing (approximate, in cents per 1M tokens)
    input_cost_per_million  = 7.5
    output_cost_per_million = 30.0
    input_tokens  = estimate_tokens(prompt)
    output_tokens = estimate_tokens(response)
    ((input_tokens * input_cost_per_million) + (output_tokens * output_cost_per_million)) / 1_000_000.0
  end

  def elapsed_ms(start)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
  end
end
```

**Implementation note:** The `call_gemini` method body depends on the exact `google-generative-ai` gem API. Refer to the gem README for the current client initialization and content generation call signature. The rest of the service skeleton is stable.

---

## 4. `HealthController` — Full Implementation

Replace the Phase 3 stub:

```ruby
class HealthController < ApplicationController
  skip_before_action :require_authentication

  def llm
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    ping_template = AiTemplate.find_by(name: "health_ping")

    if ping_template.nil?
      return render json: { status: "unconfigured",
                            message: "health_ping template not seeded" }, status: :ok
    end

    result = GeminiService.generate(template: "health_ping", variables: {}, user: nil)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

    render json: { status: "ok", response: result, duration_ms: duration_ms }

  rescue => e
    render json: { status: "error", message: e.message }, status: :service_unavailable
  end
end
```

---

## 5. Error Partial

`app/views/shared/_ai_error.html.erb` — reusable across all demo apps:

```erb
<div class="alert alert-danger">
  <h5 class="alert-heading">Something went wrong</h5>
  <% case error_type %>
  <% when :budget_exceeded %>
    <p>You've reached your daily AI request limit. Come back tomorrow!</p>
  <% when :gatekeeper_blocked %>
    <p>Your input couldn't be processed. Please revise it and try again.</p>
  <% when :timeout %>
    <p>The AI took too long to respond. Please try again.</p>
  <% else %>
    <p>An unexpected error occurred. Please try again.</p>
  <% end %>
  <%= button_to "Try again", request.path, method: :get, class: "btn btn-outline-danger btn-sm" %>
</div>
```

---

## Acceptance Criteria

- [ ] `AiTemplate` can be created and saved; `variable_names` returns correct list from `{{...}}` placeholders
- [ ] `AiTemplate#interpolate` substitutes all variables correctly
- [ ] `LlmRequest` creates with correct associations; all status scopes return correct records
- [ ] `AiGatekeeper.check!` raises `GatekeeperError` for inputs over 5000 characters
- [ ] `AiGatekeeper.check!` raises `GatekeeperError` for prompt injection patterns
- [ ] `AiBudgetChecker.check!` raises `BudgetExceededError` when daily limit is reached
- [ ] `AiBudgetChecker#remaining_calls` returns correct count
- [ ] `GeminiService.generate` with a valid template and API key returns a string response
- [ ] Every successful call writes a `LlmRequest` row with status `success`, token counts, duration, and cost
- [ ] A timeout writes a `LlmRequest` row with status `timeout`
- [ ] A gatekeeper block writes a `LlmRequest` row with status `gatekeeper_blocked`
- [ ] A budget block writes a `LlmRequest` row with status `budget_exceeded`
- [ ] `GET /up/llm` returns `{"status":"ok"}` when Gemini is reachable (requires seeded `health_ping` template)
- [ ] `GET /up/llm` returns 503 when Gemini is unreachable
