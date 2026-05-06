# Open Demo Starter - Product Requirements Document

**Document Version:** 2.0
**Last Updated:** May 1, 2026
**Purpose:** Specification for the open source Rails 8 boilerplate that all GitHub demo apps are built on top of.
**License:** MIT

---

## 1. Product Overview

### Summary

The Open Demo Starter is a minimal, open source Ruby on Rails 8 foundation for building single-purpose AI-powered demo apps. Each demo app in the indie hacker GitHub portfolio starts from this base and layers on a domain-specific feature, a unique accent color, and a UX pattern of its own choice.

The boilerplate solves the same problem for demos that the Core SaaS Boilerplate solves for production apps: it eliminates repetitive scaffolding so every new demo can ship its differentiated feature in days, not weeks. It also embeds a small, deliberate set of AI operational guardrails (call budgets, timeouts, request logging, a gatekeeper, visible raw responses) so that every demo handles the predictable failure modes of LLM-powered features without each app reinventing them.

### Target Use Case

- Public GitHub portfolio of Rails 8 plus AI demo apps
- Each demo isolates the single most valuable feature of a corresponding production SaaS app
- Demos are clonable, run locally, and showcase one tool from a larger suite
- Open source under MIT license to invite community engagement and trust
- Designed to be readable as a portfolio: visitors should be able to clone, run, and understand the AI design decisions in under 30 minutes

### What This Is NOT

- Not multi-tenant (no `acts_as_tenant`, no organizations, no memberships)
- Not a production deployment template (no Kamal, no Stripe, no Mailjet)
- Not a Devise-based app (Rails 8 native authentication only)
- Not a kitchen-sink starter (no blog CMS, no file uploads, no marketing site builder)
- Not a marketing site template (just a placeholder home page)
- Not a RAG framework or vector DB integration (single-shot prompts only; see Section 10 for rationale)

### Key Positioning

- **Single-developer friendly.** The whole codebase is small enough to read in an afternoon.
- **Rails 8 idiomatic.** Native auth, Solid Queue (optional), Bootstrap, Stimulus, Turbo.
- **AI-ready with operational sense.** Gemini service wrapped in a request log, gatekeeper, budget cap, and timeout layer. Templates are data, not code, so prompts can be edited and tested in the admin UI without restarting the server.
- **Customizable in 10 minutes.** One config file changes app name, accent color, tagline.

---

## 2. Technical Stack

| Layer | Choice | Rationale |
|---|---|---|
| Framework | Ruby on Rails 8 | Latest, native auth, native asset pipeline |
| Database | PostgreSQL 15+ | Production parity, simple to install locally |
| Authentication | Rails 8 native (`has_secure_password`, sessions) | No Devise, no extra gems, demonstrates Rails 8 |
| Authorization | None for demo data; one `admin:boolean` flag for admin pages | Demos are single-user; no role complexity |
| Frontend | Bootstrap 5 (dark mode) | Fast to style, no build tools, professional look |
| JS | Stimulus + Turbo | Rails 8 default, no React, no custom bundlers |
| AI | Google Gemini via `google-generative-ai` gem | Free tier, easy API key, fast responses |
| Testing | RSpec | Model specs and request specs only |
| Mailer (dev only) | `letter_opener` | View password reset emails locally |
| CI | GitHub Actions (RSpec only) | Lightweight, free for public repos |
| Rate limiting | Rails 8 native `rate_limit` | Built in, no third-party gem |

---

## 3. Authentication

### Methods

- Email and password with `has_secure_password`
- Session-based login using Rails 8's built-in session store
- Password reset via signed token, email rendered locally via `letter_opener`

### Out of Scope (intentional)

- No OAuth (Google, GitHub, etc.)
- No magic links
- No two-factor authentication
- No email verification (the demo is public; users sign up and use it immediately)
- No reCAPTCHA

### Pages

| Page | Path | Purpose |
|---|---|---|
| Sign up | `/sign_up` | Create account with email and password |
| Sign in | `/sign_in` | Log in with email and password |
| Sign out | `DELETE /sign_out` | End session |
| Forgot password | `/passwords/new` | Request reset email |
| Reset password | `/passwords/edit?token=...` | Set new password from email link |

### Behavior

- After sign up, user is logged in automatically and redirected to the home dashboard
- After sign in, user is redirected to the home dashboard
- Unauthenticated visitors hitting protected routes are redirected to sign in
- The home dashboard greets the user by their first name and shows a placeholder for the demo feature
- The first user seeded into the database is an admin (see Section 11)

---

## 4. Data Model

### User

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | Primary key |
| `email` | string | Unique, lowercased, indexed |
| `password_digest` | string | bcrypt via `has_secure_password` |
| `name` | string | Display name |
| `admin` | boolean | Default false; seeded user is true |
| `created_at` | datetime | |
| `updated_at` | datetime | |

### AiTemplate

The prompt is the product. Templates are stored as data so the author can edit and test them in the admin UI without restarting the server.

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `name` | string | Unique, indexed. Used as lookup key (e.g., `course_outline_v1`) |
| `description` | string | Free-form note for the author |
| `system_prompt` | text | Sent as system instruction to Gemini |
| `user_prompt_template` | text | Supports `{{variable}}` interpolation |
| `model` | string | Default `gemini-2.0-flash` |
| `max_output_tokens` | integer | Default 2000 |
| `temperature` | decimal | Default 0.7 |
| `notes` | text | Author's notes (variations to try, what works, what fails) |
| `created_at` | datetime | |
| `updated_at` | datetime | |

### LlmRequest

Every Gemini call is logged. This is the operational backbone.

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `user_id` | uuid | Foreign key |
| `ai_template_id` | uuid | Foreign key (nullable for ad-hoc calls) |
| `template_name` | string | Denormalized for log durability if template is deleted |
| `status` | string | `success`, `error`, `timeout`, `gatekeeper_blocked`, `budget_exceeded` |
| `prompt_token_count` | integer | Estimated, from input length |
| `response_token_count` | integer | Estimated, from output length |
| `duration_ms` | integer | End-to-end Gemini call duration |
| `cost_estimate_cents` | decimal | Calculated from token counts and model pricing |
| `error_message` | text | Populated on failure |
| `created_at` | datetime | Indexed; used for daily budget calculation |

### PasswordReset

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `user_id` | uuid | Foreign key |
| `token` | string | Unique, indexed |
| `expires_at` | datetime | 30 minutes from creation |
| `used_at` | datetime | Nil until consumed |

### What's Intentionally Missing

- No `Organization`, no `Membership`, no `Invitation`
- No `Subscription`, no `SubscriptionPlan`
- No `BlogPost`
- No `LoginHistory` (login activity inferred from sessions if needed)

Each demo app adds its own 3 to 5 domain models on top of this. All domain records belong to a user via `belongs_to :user` and are queried as `current_user.records`.

---

## 5. Routes

```
GET    /                       home#index           Public marketing-lite landing page
GET    /dashboard              dashboard#show       Logged-in home (placeholder for demo feature)

GET    /sign_up                registrations#new
POST   /sign_up                registrations#create

GET    /sign_in                sessions#new
POST   /sign_in                sessions#create
DELETE /sign_out               sessions#destroy

GET    /passwords/new          passwords#new
POST   /passwords              passwords#create
GET    /passwords/edit         passwords#edit
PATCH  /passwords/:token       passwords#update

# Admin namespace (admin-only)
GET    /admin                  admin/dashboard#show     At-a-glance stats
GET    /admin/users            admin/users#index        User list (read-only)
GET    /admin/llm_requests     admin/llm_requests#index Recent AI calls (last 100)
GET    /admin/ai_templates     admin/ai_templates#index Template list
GET    /admin/ai_templates/:id/edit  admin/ai_templates#edit
PATCH  /admin/ai_templates/:id admin/ai_templates#update
POST   /admin/ai_templates/:id/test  admin/ai_templates#test  Live test endpoint

GET    /up                     rails#health           Rails 8 default
GET    /up/llm                 health#llm             Gemini connectivity check
```

All HTML responses (the live test endpoint returns a Turbo Stream). No JSON API routes.

---

## 6. Controllers

### `ApplicationController`

- `before_action :require_authentication` (skipped on unauthenticated controllers)
- Helper methods: `current_user`, `signed_in?`
- Sets `Current.user` for thread-safe access
- Handles `ActiveRecord::RecordNotFound` with a flash and redirect

### `Admin::BaseController`

- Inherits from `ApplicationController`
- `before_action :require_admin`
- Renders 404 (not 403) on unauthorized access to avoid leaking the existence of the admin namespace

### `HomeController`, `DashboardController`, `RegistrationsController`, `SessionsController`, `PasswordsController`

As described in v1 of this PRD. Each demo app overrides `HomeController#index` and `DashboardController#show`.

### `Admin::DashboardController`, `Admin::UsersController`, `Admin::LlmRequestsController`, `Admin::AiTemplatesController`

See Section 11.

### `HealthController`

- `llm`: Sends a tiny "ping" prompt to Gemini and reports up/down with response time. Used for monitoring.

---

## 7. Views and Layout

### `layouts/application.html.erb`

- HTML element with `data-bs-theme="dark"` for Bootstrap dark mode
- Top navbar with app name (left), nav links (center, optional), and user dropdown or sign-in link (right)
- Admin link in the user dropdown if `current_user.admin?`
- Flash messages container (Turbo-Stream-friendly)
- Yield for page content
- Footer with: app tagline, MIT license badge linking to `LICENSE`, "Built with the Open Demo Starter" link, link to author's site, and a small AI disclaimer (`AI-generated content can be incorrect. Verify before acting.`)

### Auth Views, Public Views, Mailer Views

As described in v1 of this PRD.

### Admin Views

| View | Notes |
|---|---|
| `admin/dashboard/show.html.erb` | Counts: total users, requests today, requests this week, total templates. Two cards. |
| `admin/users/index.html.erb` | Table: email, joined, AI calls today, AI calls (lifetime), last seen |
| `admin/llm_requests/index.html.erb` | Table: created_at, user email, template name, status, duration_ms, tokens, cost. Filterable by status. Last 100 by default. |
| `admin/ai_templates/index.html.erb` | Table: name, model, updated_at, edit link |
| `admin/ai_templates/edit.html.erb` | Two-column layout: left is the editor (system prompt textarea, user prompt template textarea, model dropdown, max_output_tokens input, temperature slider, notes); right is the test panel (variable inputs auto-detected from `{{}}` placeholders, test button, response preview, token count, duration). |

---

## 8. Customization Points

These are the explicit places each demo app overrides to feel different.

### Branding

- `APP_NAME`, `APP_TAGLINE`, `APP_DESCRIPTION` env vars

### Color

One CSS custom property in `app/assets/stylesheets/application.css`:
```css
:root {
  --accent: #1d4ed8;
  --accent-hover: #1e40af;
}
```

### UX Pattern

Each demo picks its own pattern from `UX_Patterns_Guide.md` (card grid, kanban, wizard, form-then-result, dashboard, etc.). The boilerplate ships a clean dashboard placeholder.

### Layout Identity

Each demo can change navbar style, Bootstrap variants, font choice, and card vs. table vs. list-group layouts.

### AI Templates

Each demo seeds one or more `AiTemplate` records in `db/seeds.rb`. The demo's controller calls `GeminiService.generate(template: "name", variables: {...})`. The author iterates on prompts in the admin UI.

---

## 9. Gemini Integration

### The Service

`app/services/gemini_service.rb`:

```ruby
class GeminiService
  class GeminiError < StandardError; end
  class GatekeeperError < GeminiError; end
  class BudgetExceededError < GeminiError; end
  class TimeoutError < GeminiError; end

  def self.generate(template:, variables: {}, user: Current.user)
    new(template:, variables:, user:).generate
  end

  # Initialize, then generate:
  # 1. Look up AiTemplate by name (raise if missing)
  # 2. Run AiGatekeeper.check!(rendered_prompt, user) (raises GatekeeperError)
  # 3. Run AiBudgetChecker.check!(user) (raises BudgetExceededError)
  # 4. Begin LlmRequest record (status: pending)
  # 5. Interpolate variables into user_prompt_template
  # 6. Call Gemini with timeout (15s) and max_output_tokens from template
  # 7. On success, complete LlmRequest with token counts, duration, cost estimate
  # 8. On error/timeout, complete LlmRequest with status and error_message
  # 9. Return parsed response, or raise the appropriate GeminiError
end
```

### Configuration

- `GEMINI_API_KEY` in `.env`
- `.env.example` is committed; `.env` is gitignored
- `AI_CALLS_PER_USER_PER_DAY` (default 50)
- `AI_GLOBAL_TIMEOUT_SECONDS` (default 15)

### Calling Pattern in a Demo

```ruby
# In a controller action:
result = GeminiService.generate(
  template: "course_outline_v1",
  variables: { topic: @brief.topic, audience: @brief.audience, level: @brief.level }
)
@outline = CourseOutline.create!(course_brief: @brief, user: current_user, body: result, ...)
```

### Error Handling

Each demo wraps the call in a `rescue GeminiService::GeminiError => e` and renders a friendly error partial with a retry button. Specific error subclasses get specific messaging (budget exceeded, gatekeeper blocked, timeout). The exception is logged but the LlmRequest record already captured the failure for the admin to inspect.

### Out of Scope

- No multi-provider abstraction (Anthropic, OpenAI). Gemini only.
- No streaming responses
- No function calling at the boilerplate level (added per-demo when needed; see InterviewBump and CollectiveCRM specs)
- No automatic retries (the user clicks retry; this avoids stacking costs on transient failures)

---

## 10. AI Safety and Operational Guardrails

The boilerplate ships with a small, deliberate set of operational guardrails. They are visible in the code so visitors can read them, and minimal so they do not become the focus of the demo. The decisions here draw on three frameworks (PROTECTS, WATCHDOG, CAREFUL) that the author maintains as a working vocabulary for AI feature design.

### What the Boilerplate Provides (IN scope)

| Guardrail | Implementation | Framework reference |
|---|---|---|
| Per-user daily AI call cap | `AiBudgetChecker` service. Default 50/day, configurable via env. Friendly limit-reached page when exceeded. | WATCHDOG: Throttle, Cap |
| Pre-flight gatekeeper | `AiGatekeeper` service. Checks input length (under 5000 chars), basic prompt-injection patterns ("ignore previous instructions" etc.), and basic profanity. | PROTECTS: Prompt Injection, Stepwise; WATCHDOG: Gatekeeper |
| Hard output cap | `max_output_tokens` enforced on every Gemini call from the AiTemplate record | PROTECTS: Output length |
| Request timeout | 15-second default, configurable. Timeout rendered as a friendly retry page, not a crash. | CAREFUL: Latency |
| Full request log | `LlmRequest` table records every call with template, status, tokens, duration, cost estimate. Admin UI exposes the last 100. | WATCHDOG: Anomaly detection; GUARD: Audit |
| Visible raw response | Persisted Gemini outputs include the raw response. Every demo's UI has a "Show raw response" toggle. | CAREFUL: Accuracy; GUARD: Audit |
| Fail-soft UI | All Gemini errors render an inline alert with a retry button. The page never crashes. | GUARD: Rollback |
| AI disclaimer in layout | Footer note: "AI-generated content can be incorrect. Verify before acting." | CAREFUL: Accuracy |
| Health check endpoint | `/up/llm` does a tiny Gemini ping and reports up/down with response time | Operational |

### What the Boilerplate Deliberately Omits (OUT of scope)

Listing what the demo does not do is the more important half. It signals that each concern was considered and a deliberate choice was made.

| Omitted | Rationale |
|---|---|
| PII scrubbing on inputs | These are local-only demos with no production user data. Each demo's README warns users not to paste real personal data. A production app would add Presidio or a similar PII detection layer. |
| Content moderation API call | Gemini's built-in safety filters cover this scope. A production app would add a pre-flight call to OpenAI's moderation endpoint or similar. |
| Vector DB / RAG | Each demo is a single-shot prompt plus response. RAG complexity belongs in production apps where document search is core to value. The author uses LlamaIndex or Pinecone in production; not here. |
| Streaming responses | Synchronous calls keep the Rails app simple. Production apps with longer outputs would stream via Turbo Streams. |
| Fine-tuning | These demos use prompt engineering only. The point is to show what good prompting plus structured templates can achieve before reaching for fine-tuning. |
| Multi-provider fallback | Gemini-only by design. Production apps benefit from provider redundancy; demos benefit from one fewer dependency. |
| Sophisticated abuse detection | The gatekeeper is intentionally simple. Production needs more layered abuse detection; visitors can extend the gatekeeper service. |
| Cost dashboard for end users | The admin panel has total cost visibility; end users see their daily call count remaining, not dollar costs. |
| Watermarking and hardware fingerprinting | Belong in apps with abuse vectors that justify them. Demo apps with one user do not justify them. |
| Automatic retries on Gemini errors | Stacks cost on transient failures. The user clicks retry. |

### How This Plays in an Interview

The pattern of "small set of explicit guardrails plus an explicit list of omissions with rationale" is itself the strongest signal. Interviewers reading this section see a candidate who knows the failure modes of LLM features and chose where to spend complexity.

---

## 11. Admin Panel

The boilerplate includes a deliberately minimal admin panel for two purposes: operational visibility for the demo author and template iteration without code restarts. The author is the only intended admin.

### Authorization

- `admin:boolean` on `User` (default false)
- Seeded demo user is `admin: true`
- `Admin::BaseController` has `before_action :require_admin`
- Non-admin access returns 404 (not 403) to avoid leaking the namespace's existence
- No Pundit, no roles beyond admin/non-admin

### Pages

**Admin Dashboard (`/admin`).** Four stat cards: total users, AI calls today, AI calls this week, total templates. Recent error/timeout count for the past 24 hours. A "view recent requests" link to the request log.

**Users (`/admin/users`).** Read-only table. Columns: email, joined, AI calls today, AI calls lifetime, last seen. No edit, no delete. The point is operational visibility, not user administration.

**LLM Requests (`/admin/llm_requests`).** Last 100 calls. Columns: timestamp, user email, template name, status (badge color-coded), duration (ms), tokens (in/out), cost estimate. Filter by status. Click a row to see the full prompt and response (sanity check what the model is actually producing).

**AI Templates (`/admin/ai_templates`).** List of templates. Click to edit.

**AI Template Edit (`/admin/ai_templates/:id/edit`).** Two-column layout:

- **Left (the editor).** System prompt textarea (large), user prompt template textarea with `{{variable}}` highlighting, model dropdown, max_output_tokens input, temperature slider (0.0 to 2.0), notes textarea. Save button persists changes.
- **Right (the test panel).** Variables auto-detected from the `{{...}}` placeholders in the user prompt template. Each gets its own input (with prior test values remembered in session). "Test" button calls Gemini with the current draft (not saved). Response renders inline below the button. Token count, duration, and estimated cost are shown.

### What's NOT Included

- No template versioning or history (use git for that)
- No multi-user template ownership
- No template categorization or tags
- No A/B testing of templates
- No analytics dashboards beyond the recent requests list
- No user editing (read-only)
- No org/tenant management (this is single-user)

This list is short on purpose. Anything beyond visibility plus template iteration belongs in a production app.

---

## 12. RSpec Setup

### What's Included

- `spec/rails_helper.rb` configured with FactoryBot, Capybara (basic), and database cleaner via Rails transactional fixtures
- `spec/factories/`: user, ai_template, llm_request
- `spec/support/authentication_helpers.rb` with `sign_in_as(user)` for request specs
- `spec/support/gemini_test_double.rb`: stubs `GeminiService.generate` so tests run instantly with no API calls
- Sample specs:
  - `spec/models/user_spec.rb` (validations, password digest, admin?)
  - `spec/models/ai_template_spec.rb` (validations, variable extraction)
  - `spec/models/llm_request_spec.rb` (associations, status scopes)
  - `spec/services/gemini_service_spec.rb` (gatekeeper integration, budget integration, log writing, error paths)
  - `spec/services/ai_gatekeeper_spec.rb` (length check, injection patterns)
  - `spec/services/ai_budget_checker_spec.rb` (under cap, at cap, over cap)
  - `spec/requests/sessions_spec.rb`, `registrations_spec.rb`, `passwords_spec.rb`
  - `spec/requests/admin/ai_templates_spec.rb` (admin only, edit, test endpoint)

### Conventions Each Demo Inherits

- Model spec for every domain model
- Request spec for every controller action that hits Gemini
- Stub Gemini in tests using the test double
- Verify access control: a different signed-in user cannot see another user's records
- No system specs by default (added per-demo if needed)

---

## 13. Seed Data

`db/seeds.rb` creates one admin demo user:

```ruby
User.create!(
  email: "demo@example.com",
  password: "password123",
  password_confirmation: "password123",
  name: "Demo User",
  admin: true
)
```

Each demo app extends `db/seeds.rb` to create its `AiTemplate` records and any realistic sample inputs. The README mentions the seeded credentials.

---

## 14. README Template

(Unchanged from v1; see prior version. Each demo extends with app-specific "Why I built this" copy.)

The boilerplate's README itself adds two sections:

- **AI Safety Posture.** Brief explanation of what the boilerplate enforces and what it deliberately omits, mirroring Section 10. Visitors who care about responsible AI design see this immediately.
- **Cost.** Each demo's prompt seeds use `gemini-2.0-flash`, the cheapest current model. A user running the demo locally with the free tier will not be charged for typical use.

---

## 15. File Structure (Summary)

```
.
├── app/
│   ├── controllers/
│   │   ├── application_controller.rb
│   │   ├── home_controller.rb
│   │   ├── dashboard_controller.rb
│   │   ├── registrations_controller.rb
│   │   ├── sessions_controller.rb
│   │   ├── passwords_controller.rb
│   │   ├── health_controller.rb
│   │   └── admin/
│   │       ├── base_controller.rb
│   │       ├── dashboard_controller.rb
│   │       ├── users_controller.rb
│   │       ├── llm_requests_controller.rb
│   │       └── ai_templates_controller.rb
│   ├── models/
│   │   ├── application_record.rb
│   │   ├── current.rb
│   │   ├── user.rb
│   │   ├── ai_template.rb
│   │   ├── llm_request.rb
│   │   └── password_reset.rb
│   ├── services/
│   │   ├── gemini_service.rb
│   │   ├── ai_gatekeeper.rb
│   │   └── ai_budget_checker.rb
│   ├── mailers/
│   │   └── password_mailer.rb
│   ├── views/
│   │   ├── layouts/application.html.erb
│   │   ├── home/, dashboard/, registrations/, sessions/, passwords/, password_mailer/
│   │   └── admin/
│   │       ├── dashboard/
│   │       ├── users/
│   │       ├── llm_requests/
│   │       └── ai_templates/
│   ├── javascript/controllers/
│   └── assets/stylesheets/
├── bin/setup
├── config/routes.rb, environments/
├── db/migrate/, seeds.rb
├── spec/
├── .env.example
├── .gitignore
├── Gemfile
├── LICENSE         # MIT
└── README.md
```

---

## 16. Customization Checklist (For Each New Demo App)

- [ ] Clone the boilerplate as a new GitHub repo
- [ ] Update `APP_NAME`, `APP_TAGLINE`, `APP_DESCRIPTION` in `.env.example` and `.env`
- [ ] Set the accent color in `app/assets/stylesheets/_accent.scss`
- [ ] Replace `home/index.html.erb` with the demo's landing pitch
- [ ] Add the 3 to 5 domain models for the demo
- [ ] Generate migrations and run them
- [ ] Add domain controllers, views, and routes
- [ ] Add the demo's `AiTemplate` records to `db/seeds.rb`
- [ ] Wire the controller to call `GeminiService.generate(template: "...", variables: {...})`
- [ ] Test the template in the admin UI; iterate on the prompt; copy the final version back to the seed
- [ ] Add seed data with realistic sample inputs for the domain models
- [ ] Write model specs and request specs for the new feature, stubbing Gemini
- [ ] Update README with app-specific description, screenshot, and "Why I built this"
- [ ] Add an Open Graph image and meta tags
- [ ] Set up GitHub Actions to run RSpec on push

---

## 17. Versioning and Updates

The boilerplate is its own GitHub repo. Each demo is a separate repo that started as a clone (not a fork) of the boilerplate. When the boilerplate gets meaningful improvements (a security patch, a Rails minor upgrade), each demo can opt-in by cherry-picking the relevant commits.

Tag boilerplate releases with semver (`v2.0.0`, `v2.1.0`, etc.) so demos can reference which version they started from in their README.

### Migration from v1.0 to v2.0

Demos built on v1.0 (without the AI template, request log, gatekeeper, or admin panel) can adopt v2.0 incrementally:

1. Add the migration for `AiTemplate`, `LlmRequest`, and the `admin` field on User
2. Add the three new services (gemini_service.rb rewrite, ai_gatekeeper.rb, ai_budget_checker.rb)
3. Move existing inline prompts into AiTemplate seed records
4. Update controller calls from `GeminiService.generate(prompt: ...)` to `GeminiService.generate(template: "...")`
5. Add the admin namespace and views

---

## 18. Out of Scope (Reaffirmed)

This list is duplicated and bolded because the temptation to add features will be strong:

- **No multi-tenancy.** Demos are user-scoped, full stop.
- **No Stripe.** Demos are free, local, open source.
- **No background jobs by default.** Gemini calls are synchronous; if a demo needs async, it adds Solid Queue itself.
- **No file uploads.** If a demo needs them, it adds Active Storage itself.
- **No production deployment.** Demos run on localhost. The README does not include Kamal, Render, Heroku, or Fly instructions.
- **No internationalization.** English only.
- **No analytics.** No Plausible, no Google Analytics, no Mixpanel.
- **No RAG, no vector DB, no embeddings.** Single-shot prompts only.
- **No streaming, no function calling at the boilerplate level.** Per-demo if needed.
- **No multi-provider AI.** Gemini only.
- **No PII scrubbing, no content moderation API.** Demo apps with no production data do not need them; they are explicit production-grade features.
- **No fine-tuning, no model training.** Prompt engineering and templates only.

---

*v2.0 - Open Demo Starter PRD. Adds AI Safety and Operational Guardrails (Section 10), Admin Panel for user visibility and template iteration (Section 11), AiTemplate and LlmRequest data models, AiGatekeeper and AiBudgetChecker services, and an explicit out-of-scope list for AI features. Templates move from inline prompts to data-driven records the author can edit and test in the browser. Every Gemini call is now logged, time-bounded, token-bounded, gate-checked, and budget-checked. The omissions list is the more important half: it signals that each concern was considered and a deliberate choice was made.*
