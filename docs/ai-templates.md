# AI Templates Guide

This guide covers everything needed to build, configure, test, and call Gemini AI templates in Open Demo Starter and any demo app built on it.

For safety rules (guardrails, budget, gatekeeper), see [`ai-guardrails.md`](ai-guardrails.md).

---

## How It Works

Every AI feature is built around three objects:

| Object | Role |
|---|---|
| `AiTemplate` | Stores the prompt template, model, and generation settings in the database |
| `GeminiService` | Executes the full gated flow: validate → budget-check → log → call → return |
| `LlmRequest` | Audit row written for every call — success, failure, timeout, or block |

The flow for a single AI call:

```
Controller calls GeminiService.generate(template:, variables:)
  → Look up AiTemplate by name
  → Interpolate {{variables}} into user_prompt_template
  → AiGatekeeper blocks bad inputs
  → AiBudgetChecker enforces daily cap
  → POST to Gemini API (v1beta, gemini-2.5-flash)
  → Write LlmRequest row (status, tokens, duration, cost)
  → Return response text string
```

---

## The Gemini API Connection

The app calls Google's Generative Language API directly via Faraday (no gem wrapper):

```
POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={API_KEY}
```

**Working models** (confirmed with Google AI Studio free-tier keys):
- `gemini-2.5-flash` — default, fast, low cost
- `gemini-2.5-pro` — higher quality, slower, higher cost

**Do not use**: `gemini-2.0-flash` (deprecated for new API keys), `gemini-1.5-flash` / `gemini-1.5-pro` (not available in v1beta for new keys).

**System prompts** are prepended to the user message — the v1beta REST API does not support a separate `system_instruction` field. The service handles this automatically:

```ruby
# GeminiService#call_gemini — happens automatically
full_prompt = [ai_template.system_prompt.presence, rendered_prompt].compact.join("\n\n")
```

This means the system prompt is fully effective — just implemented inline rather than as a separate API parameter.

---

## AiTemplate Fields

| Field | Type | Purpose |
|---|---|---|
| `name` | string | Unique identifier used to look up the template in code (`"my_feature_v1"`) |
| `system_prompt` | text | Sets the AI's role and behavior. Prepended to every request. |
| `user_prompt_template` | text | The prompt sent to the model. Use `{{variable}}` for dynamic content. |
| `model` | string | Gemini model name. Default: `gemini-2.5-flash` |
| `max_output_tokens` | integer | Hard cap on response length |
| `temperature` | decimal | Randomness. 0.0 = deterministic, 1.0 = creative, 2.0 = chaotic |
| `description` | string | Human-readable description shown in admin UI |
| `notes` | text | Internal notes for developers |

---

## Creating a Template

### Step 1: Add it to `db/seeds.rb`

```ruby
AiTemplate.find_or_create_by!(name: "recipe_generator_v1") do |t|
  t.description          = "Generates a recipe from a list of ingredients."
  t.system_prompt        = "You are a professional chef. Write clear, practical recipes with exact measurements."
  t.user_prompt_template = "Create a recipe using these ingredients: {{ingredients}}. Dietary restrictions: {{restrictions}}."
  t.model                = "gemini-2.5-flash"
  t.max_output_tokens    = 1500
  t.temperature          = 0.7
  t.notes                = "Used by RecipesController#generate."
end
```

**Naming convention:** `feature_name_v1` — always version the name. When you change the prompt significantly, create `_v2` rather than updating `_v1` in place so existing `LlmRequest` rows still reference a valid template name.

### Step 2: Run seeds

```bash
rails db:seed
```

### Step 3: Test in the admin panel

Go to **Admin → AI Templates**, click **Edit** on your new template, and use **Test This Template** to verify the output before writing any controller code.

---

## Variable Interpolation

Templates use `{{variable_name}}` syntax (double curly braces):

```
Create a {{length}}-word summary of the following text for a {{audience}} audience:

{{content}}
```

The admin test panel automatically detects variables and renders an input for each one. In code:

```ruby
template.variable_names
# => ["length", "audience", "content"]

template.interpolate(length: "200", audience: "executive", content: "...")
# => "Create a 200-word summary of the following text for a executive audience:\n\n..."
```

**Rules:**
- Variable names must be word characters only: `[a-z_]`
- Missing variables are left as `{{variable_name}}` in the rendered prompt — catch this in tests
- Never put user-supplied content directly in `system_prompt` — only in `user_prompt_template` variables

---

## Calling GeminiService from a Controller

### Basic pattern

```ruby
class RecipesController < ApplicationController
  def generate
    @result = GeminiService.generate(
      template:  "recipe_generator_v1",
      variables: {
        ingredients:  params[:ingredients],
        restrictions: params[:dietary_restrictions].presence || "none"
      }
    )
  rescue GeminiService::BudgetExceededError
    render partial: "shared/ai_error", locals: { error_type: :budget_exceeded }
  rescue GeminiService::GatekeeperError
    render partial: "shared/ai_error", locals: { error_type: :gatekeeper_blocked }
  rescue GeminiService::TimeoutError
    render partial: "shared/ai_error", locals: { error_type: :timeout }
  rescue GeminiService::GeminiError
    render partial: "shared/ai_error", locals: { error_type: :error }
  end
end
```

`GeminiService.generate` returns the response text as a plain string on success.

### With Turbo Stream

For inline AI results without a page reload:

```ruby
# controller
def generate
  @result = GeminiService.generate(
    template:  "recipe_generator_v1",
    variables: { ingredients: params[:ingredients], restrictions: params[:restrictions] }
  )
  # renders generate.turbo_stream.erb on success
rescue GeminiService::GeminiError => e
  @error_type = case e
    when GeminiService::BudgetExceededError then :budget_exceeded
    when GeminiService::GatekeeperError     then :gatekeeper_blocked
    when GeminiService::TimeoutError        then :timeout
    else :error
  end
  render turbo_stream: turbo_stream.update("result", partial: "shared/ai_error",
                                            locals: { error_type: @error_type })
end
```

```erb
<%# generate.turbo_stream.erb %>
<%= turbo_stream.update "result" do %>
  <div class="card mt-3">
    <div class="card-body">
      <%= simple_format @result %>
    </div>
  </div>
<% end %>
```

---

## The `shared/_ai_error` Partial

Use this for all AI error states — it renders a consistent error message based on the error type:

```erb
<%= render "shared/ai_error", error_type: :budget_exceeded %>
<%= render "shared/ai_error", error_type: :gatekeeper_blocked %>
<%= render "shared/ai_error", error_type: :timeout %>
<%= render "shared/ai_error", error_type: :error %>
```

Never write custom inline error messages for AI failures — always use this partial.

---

## Writing Good Prompts

### System prompt guidelines

The system prompt sets the AI's persistent role. It is prepended to every request for this template.

```
# Good — specific role, specific output format
You are a senior Ruby on Rails developer reviewing pull requests. 
Respond with a numbered list of issues found. Be direct and concise.
If the code looks good, say "LGTM" and explain why.

# Bad — vague, no output format specified
You are a helpful assistant. Help the user with code.
```

### User prompt template guidelines

```
# Good — structured, all dynamic content in variables
Review this {{language}} code for security vulnerabilities:

```{{code}}```

Focus on: SQL injection, XSS, authentication issues.
Output format: one issue per line, with severity (HIGH/MEDIUM/LOW).

# Bad — prompt logic hardcoded, no variables
Review this Ruby code for security vulnerabilities: {{code}}
```

### Temperature guide

| Task type | Temperature |
|---|---|
| Health checks, structured data extraction | 0.0 – 0.2 |
| Summaries, analysis, Q&A | 0.3 – 0.5 |
| General writing assistance | 0.6 – 0.8 |
| Creative writing, brainstorming | 0.9 – 1.2 |
| Experimental / highly varied output | 1.3 – 2.0 |

### Token budget

`max_output_tokens` is a hard cap. Set it 20–30% above the longest reasonable response. A recipe shouldn't need more than 800 tokens; a code review rarely exceeds 1500.

---

## Testing Templates

### Admin test panel

The fastest way to iterate. Go to **Admin → AI Templates → Edit**, fill in the variable inputs under **Test This Template**, and click **Run Test**. The result appears inline. The LlmRequest is written to the database so you can see token counts and duration.

Check these cases before shipping:
- [ ] Normal input — does the output match expectations?
- [ ] Empty variable — what does the model do with a blank `{{topic}}`?
- [ ] Very long input — does it stay under `max_output_tokens`?
- [ ] Prompt injection attempt — try `"ignore all previous instructions"` in a variable field

### RSpec specs

Never make real Gemini API calls in tests. Use the stubs from `spec/support/gemini_test_double.rb`:

```ruby
# Stub a successful response
gemini_returns("Here is your recipe: ...")

# Stub an error
gemini_raises(GeminiService::TimeoutError)
gemini_raises(GeminiService::BudgetExceededError)
```

These stubs work at the `GeminiService.generate` level. All logging, gatekeeper, and budget checks still run normally — only the actual API call is stubbed.

```ruby
# spec/requests/recipes_spec.rb
RSpec.describe "Recipes", type: :request do
  let(:user) { create(:user) }

  describe "POST /recipes/generate" do
    before { sign_in_as(user) }

    context "when Gemini returns a response" do
      it "renders the result" do
        gemini_returns("Pasta carbonara: ...")
        post generate_recipes_path, params: { ingredients: "pasta, eggs" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Pasta carbonara")
      end
    end

    context "when Gemini times out" do
      it "renders the error partial" do
        gemini_raises(GeminiService::TimeoutError)
        post generate_recipes_path, params: { ingredients: "pasta, eggs" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.body).to include("timed out")
      end
    end
  end
end
```

---

## Admin Panel Reference

| Path | What it shows |
|---|---|
| `/admin/ai_templates` | All seeded templates with last-updated date |
| `/admin/ai_templates/:id/edit` | Edit prompt, model, settings. Test panel below the form. |
| `/admin/llm_requests` | Last 100 API calls with status, duration, token counts, errors |
| `/admin` | Dashboard — calls today, this week, error count, cost |

The **LlmRequests** log is the primary debugging tool. When a call fails, the `error_message` column contains the raw API error JSON from Google, which identifies the exact issue (wrong model name, invalid request format, budget exceeded, etc.).

---

## Checklist: Shipping a New AI Feature

- [ ] Template created in `db/seeds.rb` with versioned name (`_v1`)
- [ ] `system_prompt` defines a specific, scoped role
- [ ] All dynamic content uses `{{variables}}` — no string interpolation in the template
- [ ] `max_output_tokens` set to a sensible cap
- [ ] Tested in admin test panel: normal input, edge cases, prompt injection
- [ ] Controller rescues all four `GeminiService` error types
- [ ] Error states render `shared/_ai_error` partial
- [ ] Request spec covers success + at least one error case with stubs
- [ ] No real API calls in test suite (`gemini_returns` / `gemini_raises` used throughout)
