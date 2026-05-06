# Open Demo Starter — Build Tasks

Track progress here. Check off each item as it is completed. Each phase spec has full implementation details.

---

## Phase 1 — Rails App Foundation ✅
**Spec:** [phase_1_foundation.md](phase_1_foundation.md)

- [x] `rails new` with PostgreSQL, importmap, correct flags
- [x] UUID primary keys enabled globally in `config/application.rb`
- [x] `pgcrypto` extension migration created
- [x] Gemfile updated: `gemini-ai` (correct Ruby gem), `dotenv-rails`, `letter_opener`, `rspec-rails`, `factory_bot_rails`, `capybara`
- [x] `bundle install` succeeds
- [x] `.env.example` committed with all 6 variable stubs, zero real values
- [x] `.env` added to `.gitignore` (`.env.example` explicitly un-ignored)
- [x] Bootstrap 5 CSS and JS wired in (CDN link tag in layout)
- [x] `<html data-bs-theme="dark">` on layout
- [x] `--accent` and `--accent-hover` CSS custom properties defined
- [x] `config/routes.rb` stubbed with all routes from PRD Section 5
- [x] Stimulus + Turbo confirmed in `config/importmap.rb`
- [x] `rails db:create` succeeds (development + test DBs created, pgcrypto enabled)
- [x] `rails server` starts with no errors (verified via `rails runner`)
- [x] `GET /` returns 200

---

## Phase 2 — Authentication ✅
**Spec:** [phase_2_authentication.md](phase_2_authentication.md)

- [x] `CreateUsers` migration with UUID PK, email index, admin boolean
- [x] `CreatePasswordResets` migration with UUID PK, token index
- [x] `User` model: `has_secure_password`, email validations, `downcase_email`, `first_name`
- [x] `PasswordReset` model: `expired?`, `used?`, `valid_for_use?`
- [x] `Current` model with `attr_accessor :user`
- [x] `ApplicationController`: `require_authentication`, `current_user`, `signed_in?`, sets `Current.user`
- [x] `RegistrationsController`: `new`, `create` (auto sign-in, redirect to dashboard)
- [x] `SessionsController`: `new`, `create`, `destroy`
- [x] `PasswordsController`: `new`, `create`, `edit`, `update`
- [x] Rate limiting on `RegistrationsController` and `SessionsController`
- [x] `PasswordMailer#reset` with token URL
- [x] `letter_opener` configured for development
- [x] Sign-up view (Bootstrap card, flash display, link to sign-in)
- [x] Sign-in view (Bootstrap card, flash display, link to sign-up)
- [x] Forgot password view
- [x] Reset password view
- [x] Password reset email template
- [x] Full sign-up flow works end-to-end
- [x] Full sign-in / sign-out flow works end-to-end
- [x] Password reset email opens in browser via `letter_opener`
- [x] Expired / used token redirects correctly

---

## Phase 3 — Core Layout & Public Pages ✅
**Spec:** [phase_3_layout_and_pages.md](phase_3_layout_and_pages.md)

- [x] `layouts/application.html.erb` — `<head>` with CSRF tags, stylesheet, importmap
- [x] Navbar: brand left, user dropdown right, sign-in/sign-up for guests
- [x] Admin link in dropdown for admin users only
- [x] Flash messages container (Turbo-Stream-friendly, id="flash")
- [x] `flash_bootstrap_class` helper in `ApplicationHelper`
- [x] `<main class="container py-4">` wraps yield
- [x] Footer: tagline, MIT badge, "Built with Open Demo Starter", AI disclaimer
- [x] `<body class="d-flex flex-column min-vh-100">` for sticky footer
- [x] `HomeController#index` — skips auth
- [x] `home/index.html.erb` — landing page with env var branding, CTA buttons
- [x] `DashboardController#show` — requires auth
- [x] `dashboard/show.html.erb` — greeting by first name, demo placeholder card
- [x] `Admin::BaseController` — `require_admin`, returns 404 for non-admins
- [x] `HealthController#llm` — stub returning `{"status":"not_configured"}`
- [x] Named route helpers confirmed working in views (`sign_in_path`, `sign_up_path`, `sign_out_path`)
- [x] Non-admin hitting `/admin` receives 404 (not 403)
- [x] All env var branding renders correctly from `.env`

---

## Phase 4 — AI Models & Services ✅
**Spec:** [phase_4_ai_models_and_services.md](phase_4_ai_models_and_services.md)

- [x] `CreateAiTemplates` migration with all fields, unique index on `name`
- [x] `CreateLlmRequests` migration with all fields, indexes on `created_at` and `status`
- [x] `AiTemplate` model: validations, `variable_names`, `interpolate`
- [x] `LlmRequest` model: associations, status constants, all scopes (`today`, `this_week`, `successful`, `failed`, `recent`)
- [x] `AiGatekeeper` service: length check, injection patterns, profanity list
- [x] `AiBudgetChecker` service: daily count vs. env cap, `remaining_calls`
- [x] `GeminiService` skeleton: all 4 error classes defined
- [x] `GeminiService#generate`: full 9-step flow implemented
- [x] `GeminiService` — `call_gemini` wired to `gemini-ai` gem
- [x] Timeout enforced via `Timeout.timeout`
- [x] Token counts from API response (`usageMetadata`), estimate as fallback
- [x] Cost estimation (`estimate_cost`) working
- [x] Successful call writes `LlmRequest` with status `success`, token counts, duration, cost
- [x] Timeout writes `LlmRequest` with status `timeout`
- [x] Gatekeeper block writes `LlmRequest` with status `gatekeeper_blocked`
- [x] Budget block writes `LlmRequest` with status `budget_exceeded`
- [x] `HealthController#llm` updated to live Gemini ping (replaces Phase 3 stub)
- [x] `shared/_ai_error.html.erb` partial created with per-error messaging
- [ ] `GET /up/llm` returns `{"status":"ok"}` with real API key — requires seeded `health_ping` template (Phase 7)

---

## Phase 5 — Admin Panel ✅
**Spec:** [phase_5_admin_panel.md](phase_5_admin_panel.md)

- [x] `Admin::DashboardController#show` — 5 stat queries
- [x] `admin/dashboard/show.html.erb` — 4+ stat cards, recent errors card, link to requests
- [x] `Admin::UsersController#index` — users with AI call counts (no N+1)
- [x] `admin/users/index.html.erb` — read-only table with all columns
- [x] `Admin::LlmRequestsController#index` — last 100, status filter
- [x] `admin/llm_requests/index.html.erb` — table with status badges, expandable row detail
- [x] `Admin::AiTemplatesController#index` — ordered list
- [x] `Admin::AiTemplatesController#edit` — loads template
- [x] `Admin::AiTemplatesController#update` — persists changes, redirect with flash
- [x] `Admin::AiTemplatesController#test` — calls GeminiService, returns Turbo Stream
- [x] `admin/ai_templates/index.html.erb` — table with edit links
- [x] `admin/ai_templates/edit.html.erb` — two-column layout (editor left, test panel right)
- [x] `admin/ai_templates/_test_result.html.erb` partial
- [x] `admin/ai_templates/_test_error.html.erb` partial
- [x] `variable-inputs` Stimulus controller — auto-detects `{{...}}` from textarea
- [x] `temperature-slider` Stimulus controller — live value display
- [x] Model dropdown includes correct Gemini model options
- [x] Test panel "Run Test" button sends Turbo request, result renders inline
- [x] All admin routes return 404 for non-admin authenticated users
- [x] All admin routes redirect unauthenticated users to sign in

---

## Phase 6 — RSpec Test Suite ✅
**Spec:** [phase_6_rspec_test_suite.md](phase_6_rspec_test_suite.md)

- [x] `spec/rails_helper.rb` with FactoryBot, transactional fixtures, support autoload
- [x] `spec/factories/users.rb` with `:admin` trait
- [x] `spec/factories/ai_templates.rb`
- [x] `spec/factories/llm_requests.rb` with all status traits
- [x] `spec/support/authentication_helpers.rb` — `sign_in_as`
- [x] `spec/support/gemini_test_double.rb` — `gemini_returns`, `gemini_raises`
- [x] `spec/models/user_spec.rb` — validations, `first_name`, `downcase_email`, admin default
- [x] `spec/models/ai_template_spec.rb` — validations, `variable_names`, `interpolate`
- [x] `spec/models/llm_request_spec.rb` — associations, status validation, all scopes
- [x] `spec/services/ai_gatekeeper_spec.rb` — passes, length, injection, profanity
- [x] `spec/services/ai_budget_checker_spec.rb` — under/at/over limit, day boundary, remaining
- [x] `spec/services/gemini_service_spec.rb` — all 5 status outcomes, log writing
- [x] `spec/requests/sessions_spec.rb` — GET, POST valid, POST invalid, DELETE
- [x] `spec/requests/registrations_spec.rb` — GET, POST valid, POST duplicate
- [x] `spec/requests/passwords_spec.rb` — full reset flow, expired token, used token
- [x] `spec/requests/admin/ai_templates_spec.rb` — access control, edit, update, test
- [x] `.github/workflows/ci.yml` created
- [x] `bundle exec rspec` passes with zero failures (81 examples, 0 failures)
- [x] Zero real Gemini API calls during test run (call_gemini stubbed via allow_any_instance_of)
- [ ] CI passes on GitHub — pending first push

---

## Phase 7 — Seed Data, CI & Final Packaging ✅
**Spec:** [phase_7_seed_ci_packaging.md](phase_7_seed_ci_packaging.md)

- [x] `db/seeds.rb` — admin demo user (`demo@example.com` / `password123`)
- [x] `db/seeds.rb` — `health_ping` AI template
- [x] `db/seeds.rb` — `demo_placeholder_v1` AI template
- [x] `bin/setup` script created and executable (`chmod +x bin/setup`)
- [x] `bin/setup` copies `.env.example` to `.env` if missing
- [x] `.env.example` final version with inline comments for all vars
- [x] `.gitignore` final audit — `.env` blocked, `.env.example` tracked, `.DS_Store` added
- [x] `config/master.key` confirmed in `.gitignore`
- [x] `LICENSE` (MIT) file at repo root
- [x] `README.md` — Quick Start section
- [x] `README.md` — Environment variables table
- [x] `README.md` — Stack section
- [x] `README.md` — AI Safety Posture section (enforced + omitted)
- [x] `README.md` — Cost section
- [x] `README.md` — Customization section
- [x] `.github/workflows/ci.yml` — RSpec on push/PR to master, PostgreSQL service, stub API key
- [x] Security audit: no `.env` in git history
- [x] Security audit: no real API keys in any committed file
- [x] Security audit: `password123` only in seeds, README, docs, and CLAUDE.md (demo credentials)
- [x] Security audit: no `binding.pry` or `byebug` in source
- [x] `bundle exec rspec` passes — 81 examples, 0 failures
- [ ] GitHub Actions CI passes — pending first push to GitHub
- [ ] Repo tagged `v2.0.0` — pending CI verification

---

## Summary

| Phase | Description | Status |
|---|---|---|
| 1 | Rails App Foundation | ✅ Complete |
| 2 | Authentication | ✅ Complete (end-to-end flow verified in Phase 3) |
| 3 | Core Layout & Public Pages | ✅ Complete |
| 4 | AI Models & Services | ✅ Complete |
| 5 | Admin Panel | ✅ Complete |
| 6 | RSpec Test Suite | ✅ Complete |
| 7 | Seed Data, CI & Final Packaging | ✅ Complete (pending Phase 6 for rspec/CI/tag) |
