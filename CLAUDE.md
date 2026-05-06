# Open Demo Starter — AI Assistant Context

This file provides essential context for AI assistants working on this Rails 8 demo boilerplate and any demo apps built from it.

## Reference Guides

Always consult the relevant guide before implementing — they contain proven patterns and document what breaks.

| Guide | When to use |
|---|---|
| [`docs/turbo-stimulus-patterns.md`](docs/turbo-stimulus-patterns.md) | Any Turbo Stream, Stimulus controller, Bootstrap interaction, or Editor.js work |
| [`docs/security.md`](docs/security.md) | CSP, headers, rate limiting, secrets, auth security patterns |
| [`docs/ai-templates.md`](docs/ai-templates.md) | Building AI features: creating templates, calling GeminiService, error handling, testing |
| [`docs/ai-guardrails.md`](docs/ai-guardrails.md) | Safety layer: AiGatekeeper, AiBudgetChecker, LlmRequest logging, deliberate omissions |
| [`docs/testing.md`](docs/testing.md) | RSpec factories, model specs, service specs, request specs, Gemini stubs |

---

## 🔥 STOP — READ THESE FIRST

### ❌ NO PLAIN JAVASCRIPT — STIMULUS ONLY

This app uses **Stimulus + Turbo exclusively**. Never write plain JavaScript solutions.

| ❌ NEVER | ✅ ALWAYS |
|---|---|
| `onclick="someFunction()"` | `data-action="click->controller#method"` |
| `addEventListener(...)` | Stimulus action descriptors |
| `<script>` tags in views | Stimulus controllers in `app/javascript/controllers/` |
| `document.querySelector(...)` | Stimulus targets (`data-controller-target`) |
| React, Vue, Alpine, or any other JS framework | Stimulus only |

**Why:** Inline JS is blocked by CSP, breaks Turbo navigation, and creates state management complexity this codebase deliberately avoids.

---

### 🚨 TURBO STREAM: ALWAYS `update()`, NEVER `replace()`

**`replace()` destroys DOM elements and breaks Stimulus bindings after the first use.**

```ruby
# ❌ WRONG — breaks after first submit
turbo_stream.replace("target-id", content)

# ✅ CORRECT — works every time
turbo_stream.update("target-id", content)
```

Use `replace()` only for truly one-time page sections that will never be re-rendered. Use `update()` for everything else: forms, AI results, flash messages, dynamic content.

---

### ❌ NO BACKWARD COMPATIBILITY

This is a demo boilerplate with no production customers. When rewriting a feature:

1. Delete the old implementation completely
2. Update every caller to the new pattern
3. Remove unused columns, routes, views, and methods
4. Never add shims, aliases, or "supports both" code paths

---

### ❌ NEVER HARDCODE APP NAME OR BRANDING

Every reference to the app name, tagline, or description must come from environment variables:

```erb
<%# ✅ CORRECT %>
<%= ENV.fetch("APP_NAME", "Open Demo Starter") %>

<%# ❌ WRONG %>
Open Demo Starter
```

The same rule applies in mailer subjects, page titles, and footer copy.

---

### ❌ NEVER START THE RAILS SERVER AUTOMATICALLY

Always tell the user to start the server manually in a separate terminal. Never run `rails server` or `bin/dev` as part of a task.

---

### ❌ NEVER RUN RSPEC OR GIT PUSH AUTOMATICALLY

Always ask the user to run tests and git operations manually:
- "Please run `bundle exec rspec` and share the output."
- "Please review and commit these changes."

---

## Tech Stack

| Layer | Choice | Rule |
|---|---|---|
| Framework | Rails 8.1 | No upgrades without explicit request |
| Database | PostgreSQL 15+ with UUID PKs | `pgcrypto` extension required |
| Auth | Rails 8 native (`has_secure_password`, sessions) | No Devise, no OAuth |
| Authorization | `admin:boolean` on User | No Pundit, no roles beyond admin/non-admin |
| Asset Pipeline | Propshaft | No Sprockets, no Webpack, no Node build tools |
| CSS | Bootstrap 5 (dark mode, CDN) | No Tailwind, no SCSS compilation |
| JavaScript | Stimulus + Turbo via importmap | No React, Vue, Alpine, or npm packages |
| Rich Text | Editor.js | No Action Text, no Trix |
| AI | Gemini via `gemini-ai` gem | No OpenAI, no Anthropic at boilerplate level |
| Background Jobs | Solid Queue | No Redis, no Sidekiq |
| Caching | Solid Cache | No Redis |
| Cable | Solid Cable | No Redis |
| Testing | RSpec | No Minitest |
| Dev Email | `letter_opener` | No real email in development |

### Solid Stack Rule
**Always use the Solid Stack. Never add Redis, Sidekiq, or any external queue/cache dependency.** Solid Queue, Solid Cache, and Solid Cable handle everything at this scale.

---

## What This App Is NOT

Do not add these features. They belong in production SaaS apps, not demo boilerplates.

- **No multi-tenancy** — no `acts_as_tenant`, no organizations, no memberships
- **No Stripe** — demos are free and local
- **No Kamal / production deployment** — runs on localhost only
- **No OAuth** — email/password only
- **No file uploads** — no Active Storage
- **No background jobs by default** — Gemini calls are synchronous; add Solid Queue per-demo if needed
- **No RAG or vector DB** — single-shot Gemini prompts only
- **No streaming responses** — synchronous calls only
- **No internationalization** — English only
- **No analytics** — no GA, Plausible, or Mixpanel

When asked to add any of the above, decline and explain that it is out of scope for the boilerplate.

---

## Application Structure

```
app/
  controllers/
    application_controller.rb     # require_authentication, current_user, Current.user
    home_controller.rb            # public landing page (skips auth)
    dashboard_controller.rb       # logged-in home
    registrations_controller.rb   # sign up
    sessions_controller.rb        # sign in / sign out
    passwords_controller.rb       # forgot / reset password
    health_controller.rb          # /up/llm Gemini ping
    admin/
      base_controller.rb          # require_admin, returns 404 for non-admins
      dashboard_controller.rb
      users_controller.rb
      llm_requests_controller.rb
      ai_templates_controller.rb  # includes #test Turbo Stream endpoint
  models/
    user.rb                       # has_secure_password, admin boolean
    ai_template.rb                # variable_names, interpolate
    llm_request.rb                # every Gemini call logged here
    password_reset.rb             # signed token, 30-min expiry
    current.rb                    # CurrentAttributes, holds Current.user
  services/
    gemini_service.rb             # 9-step flow: gate → budget → log → call → complete
    ai_gatekeeper.rb              # length, injection patterns, profanity
    ai_budget_checker.rb          # daily cap per user from env var
  views/
    layouts/application.html.erb  # navbar, flash, footer with AI disclaimer
    shared/_ai_error.html.erb     # reusable error partial for Gemini failures
```

---

## Core Patterns

### Authentication

```ruby
# ApplicationController sets Current.user and enforces auth
before_action :require_authentication

def current_user
  @current_user ||= User.find_by(id: session[:user_id])
end
```

- After sign-up or sign-in: set `session[:user_id]` and redirect to `/dashboard`
- Sign-out: clear `session[:user_id]` and redirect to `/`
- Unauthenticated visits to protected routes: redirect to `/sign_in`

### Admin Authorization

```ruby
# Admin::BaseController — returns 404, NOT 403
def require_admin
  unless current_user&.admin?
    render file: Rails.public_path.join("404.html"), status: :not_found
  end
end
```

Always return 404 for non-admin access. Never return 403, which would reveal the admin namespace exists.

### Calling Gemini

```ruby
# In a controller action
result = GeminiService.generate(
  template:  "template_name_v1",
  variables: { topic: params[:topic], audience: params[:audience] }
)
rescue GeminiService::BudgetExceededError
  render partial: "shared/ai_error", locals: { error_type: :budget_exceeded }
rescue GeminiService::GatekeeperError
  render partial: "shared/ai_error", locals: { error_type: :gatekeeper_blocked }
rescue GeminiService::TimeoutError
  render partial: "shared/ai_error", locals: { error_type: :timeout }
rescue GeminiService::GeminiError
  render partial: "shared/ai_error", locals: { error_type: :error }
```

**Never call the Gemini API directly.** Always go through `GeminiService.generate`. This ensures every call is gated, budgeted, logged, and time-bounded.

**System prompts** are prepended to the user message automatically by `GeminiService` — the v1beta REST API does not support a separate `system_instruction` field. Write the system prompt as if it will be the first paragraph the model reads before your user content.

**Working models** (confirmed with Google AI Studio free-tier API keys): `gemini-2.5-flash` (default), `gemini-2.5-pro`. Do not use `gemini-2.0-flash` or any `1.5-*` model — they return 404 on v1beta for new API keys.

### AiTemplate Variable Interpolation

Templates use `{{variable_name}}` syntax. The admin test panel auto-detects these and renders inputs.

```ruby
template.variable_names          # => ["topic", "audience"]
template.interpolate(topic: "Rails", audience: "beginners")
```

### LlmRequest Statuses

Every call writes an `LlmRequest` row. Valid statuses:
- `pending` → `success` — completed normally
- `pending` → `timeout` — Gemini took longer than `AI_GLOBAL_TIMEOUT_SECONDS`
- `pending` → `error` — unexpected Gemini error
- `gatekeeper_blocked` — never reached Gemini (AiGatekeeper failed)
- `budget_exceeded` — never reached Gemini (AiBudgetChecker failed)

---

## Bootstrap & UI Patterns

### Dark Mode

The `<html>` element always has `data-bs-theme="dark"`. Never add a theme toggle — this boilerplate is dark mode only.

### Accent Color

One customization point per demo app:

```css
/* app/assets/stylesheets/application.css */
:root {
  --accent: #1d4ed8;
  --accent-hover: #1e40af;
}
```

Use `var(--accent)` in custom styles. Never hardcode a blue hex value elsewhere.

### Flash Messages

Flash container has `id="flash"` so Turbo Streams can update it:

```erb
<div id="flash" class="container mt-3">
  <% flash.each do |type, message| %>
    <div class="alert alert-<%= flash_bootstrap_class(type) %> alert-dismissible fade show">
      <%= message %>
      <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
  <% end %>
</div>
```

Use `turbo_stream.update("flash", ...)` to push flash messages from Turbo Stream responses.

### Standard Page Structure

All pages follow this structure — no modals, no complex overlays:

```erb
<div class="container py-4">
  <div class="row">
    <div class="col">
      <h1>Page Title</h1>
      <!-- content -->
    </div>
  </div>
</div>
```

Use standard Rails CRUD pages (`index`, `show`, `new`, `edit`) and `_form.html.erb` partials. Avoid complex modal-based interactions.

---

## Editor.js

Editor.js is the rich text editor for any demo app that needs formatted content input.

- Store content as `jsonb` in PostgreSQL
- Field naming convention: `name` (string) + `description` (jsonb)
- Use the shared `editor_field` and `editor_content` view partials
- For AI compatibility: convert Editor.js JSON to markdown before sending to Gemini; convert AI markdown response back to Editor.js JSON before saving

Never use Action Text or Trix. Never use a `text` column for rich content that users edit.

---

## RSpec Testing

### What to Test

- **Model specs** — validations, scopes, helper methods
- **Service specs** — GeminiService, AiGatekeeper, AiBudgetChecker (stub Gemini API)
- **Request specs** — controller actions, auth flows, access control, redirects

No system specs by default. Each demo app adds them per-demo if needed.

### Stub Gemini in Every Spec

Never make real Gemini API calls in tests. Use the test double:

```ruby
# Allow to stub in individual examples
allow(GeminiService).to receive(:generate).and_return("Stubbed response.")
allow(GeminiService).to receive(:generate).and_raise(GeminiService::TimeoutError, "Stubbed timeout")
```

The `spec/support/gemini_test_double.rb` helper provides `gemini_returns(text)` and `gemini_raises(error_class)` convenience methods.

### Sign In Helper

```ruby
# spec/support/authentication_helpers.rb
def sign_in_as(user)
  post sign_in_path, params: { email: user.email, password: "password123" }
end
```

### Access Control — Always Verify

Every request spec for a protected route must verify:
1. Unauthenticated request redirects to sign in
2. Non-admin request to admin route returns 404 (not 403)
3. Signed-in non-owner cannot access another user's records

### Factories

```ruby
create(:user)           # regular user
create(:user, :admin)   # admin user
create(:ai_template)    # with {{variable}} in user_prompt_template
create(:llm_request, :timeout)  # use traits for status variants
```

---

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `APP_NAME` | `"Open Demo Starter"` | Navbar, title, footer |
| `APP_TAGLINE` | — | Footer, landing page |
| `APP_DESCRIPTION` | — | Landing page meta |
| `GEMINI_API_KEY` | (required) | Gemini API access |
| `AI_CALLS_PER_USER_PER_DAY` | `50` | Daily budget cap |
| `AI_GLOBAL_TIMEOUT_SECONDS` | `15` | Gemini request timeout |

Always read values with `ENV.fetch("VAR_NAME", "default")`. Never hardcode these values anywhere.

---

## Security Rules

- **CSRF** protection is on for all forms — never disable it
- **Rate limiting** on sign-in and sign-up (Rails 8 native `rate_limit`)
- **No PII in logs** — `filter_parameters` in `application.rb` must include `:password`
- **Admin namespace** returns 404 for non-admins — never 403
- **Gemini inputs** always pass through `AiGatekeeper` before reaching the API
- **`.env` is gitignored** — `.env.example` is committed with no real values
- **`config/master.key` is gitignored** — never commit it
- Never add `binding.pry` or `debugger` calls to committed code

---

## Database Conventions

- **UUID primary keys** on all models (`pgcrypto` extension)
- **Indexed columns**: `users.email` (unique), `ai_templates.name` (unique), `llm_requests.created_at`, `llm_requests.status`, `password_resets.token` (unique)
- Foreign keys use `type: :uuid`
- All timestamps are `null: false`
- Boolean columns have `default: false, null: false`

---

## Routes

All routes are HTML. No JSON API routes at the boilerplate level. The only Turbo Stream responses come from:
- `POST /admin/ai_templates/:id/test` — returns Turbo Stream to `#test-result`
- Flash message updates via `turbo_stream.update("flash", ...)`

Named route helpers (always use these in views and specs, never string paths):

```
root_path         sign_up_path      sign_in_path     sign_out_path
dashboard_path    new_password_path edit_password_path
admin_dashboard_path  admin_users_path  admin_llm_requests_path
admin_ai_templates_path  admin_edit_ai_template_path(id)
admin_ai_template_path(id)  admin_test_ai_template_path(id)
health_llm_path   rails_health_check_path
```

---

## Seeded Demo Credentials

The default seed always creates:
- **Email:** `demo@example.com`
- **Password:** `password123`
- **Admin:** `true`

Mention these in the README. Never change them in the boilerplate — each demo app can override `db/seeds.rb`.

---

## Demo App Customization Checklist

When building a new demo app on top of this boilerplate, the only changes needed are:

1. Update `APP_NAME`, `APP_TAGLINE`, `APP_DESCRIPTION` in `.env`
2. Set `--accent` color in `application.css`
3. Replace `home/index.html.erb`
4. Add 3–5 domain models (always `belongs_to :user`)
5. Add domain controllers, views, routes
6. Add `AiTemplate` seeds
7. Call `GeminiService.generate(template: "...", variables: {...})` from controllers
8. Write model and request specs for the new feature

Do not modify the auth system, admin panel, services, or layout for individual demo apps.
