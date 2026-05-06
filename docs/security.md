# Security Guide

Security patterns for Rails 8 demo apps. These are locally-hosted apps — the threat model is moderate. The goal is correct configuration, not paranoia.

---

## What Is Already Configured

| Area | What | Location |
|---|---|---|
| Auth | `has_secure_password` (bcrypt) | `User` model |
| Auth | Signed token password reset, 30-min expiry | `PasswordReset` model |
| CSRF | Rails default CSRF protection on all forms | `ApplicationController` |
| Auth | Rate limiting on sign-in and sign-up | `SessionsController`, `RegistrationsController` |
| Secrets | `.env` gitignored, `.env.example` committed | `.gitignore` |
| Secrets | `config/master.key` gitignored | `.gitignore` |
| Admin | 404 (not 403) for non-admin access | `Admin::BaseController` |
| AI | Input gatekeeper before every Gemini call | `AiGatekeeper` |
| AI | Daily budget cap per user | `AiBudgetChecker` |
| AI | 15-second timeout on Gemini calls | `GeminiService` |

---

## Content Security Policy (CSP)

The CSP initializer is generated but commented out. Enable it — it is the single most impactful browser-level security improvement.

**`config/initializers/content_security_policy.rb`:**

```ruby
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.font_src    :self, :https, :data
    policy.img_src     :self, :https, :data, "blob:"
    policy.object_src  :none
    # Nonce applied automatically — do NOT add :nonce here
    policy.script_src  :self, :https
    # :unsafe_inline required for Bootstrap dynamic styles
    policy.style_src   :self, :https, :unsafe_inline
    # Prevent clickjacking
    policy.frame_ancestors :none
  end

  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Start in report-only mode. Watch logs, then remove this line to enforce.
  config.content_security_policy_report_only = true
end
```

**Notes:**
- `:unsafe_inline` in `style_src` is required because Bootstrap applies dynamic inline styles
- Nonces for importmap and Turbo inline scripts are injected automatically — do not add `:nonce` to `script_src` in the DSL
- `frame_ancestors :none` replaces `X-Frame-Options` and prevents iframe embedding
- Start with `report_only = true`, deploy, watch logs, then remove that line to enforce

---

## Secure Headers

Create `config/initializers/security_headers.rb`:

```ruby
Rails.application.config.action_dispatch.default_headers.merge!(
  "Referrer-Policy"   => "strict-origin-when-cross-origin",
  "Permissions-Policy" => "camera=(), microphone=(), geolocation=()"
)
```

Rails 8 already sets:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: SAMEORIGIN` (superseded by CSP `frame_ancestors` once CSP is active)

---

## Rate Limiting

Rails 8 native `rate_limit` uses Solid Cache — no Redis needed.

```ruby
# app/controllers/sessions_controller.rb
rate_limit to: 10, within: 3.minutes, only: :create,
           with: -> { redirect_to sign_in_path, alert: "Too many attempts. Try again in a few minutes." }

# app/controllers/registrations_controller.rb
rate_limit to: 5, within: 10.minutes, only: :create,
           with: -> { redirect_to sign_up_path, alert: "Too many sign-up attempts. Try again later." }

# app/controllers/passwords_controller.rb
rate_limit to: 5, within: 10.minutes, only: :create,
           with: -> { redirect_to new_password_path, alert: "Too many requests. Try again later." }
```

**Testing rate limits with RSpec:** Rails `rate_limit` captures the cache store at class load time. In tests, add to `config/environments/test.rb`:

```ruby
config.action_controller.cache_store = :memory_store
```

And add a global cleanup hook in `spec/support/rate_limit_helpers.rb`:

```ruby
RSpec.configure do |config|
  config.after(:each) { ActionController::Base.cache_store.clear }
end
```

Without the global hook, rate limit counters accumulate across the test suite and cause failures after ~10 examples hit the same IP.

---

## Parameter Filtering

Ensure sensitive params never appear in logs. In `config/initializers/filter_parameter_logging.rb`:

```ruby
Rails.application.config.filter_parameters += [
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn,
  :api_key, :gemini_api_key
]
```

---

## Session Fixation

Call `reset_session` before assigning `session[:user_id]` on login. This prevents session fixation attacks where an attacker sets a known session ID before the user logs in.

```ruby
# In SessionsController#create
def create
  user = User.find_by(email: params[:email].downcase)
  if user&.authenticate(params[:password])
    reset_session                    # ← prevents session fixation
    session[:user_id] = user.id
    redirect_to dashboard_path
  else
    flash.now[:alert] = "Invalid email or password."
    render :new, status: :unprocessable_entity
  end
end
```

---

## Secret Management

### What Must Never Be Committed

| File | Contains | Status |
|---|---|---|
| `.env` | Real API keys, DB passwords | Gitignored |
| `config/master.key` | Rails credentials decryption key | Gitignored |
| `.kamal/secrets` | Deployment secrets | Not used in this app |

**Audit command** — run before any push:

```bash
git log --all --oneline -- .env           # should return nothing
git grep -i "api_key" -- ":(exclude).env.example"  # should return nothing
```

### `.env.example`

Always up-to-date with all required variables, placeholder values only, inline comments explaining each:

```bash
GEMINI_API_KEY=your_gemini_api_key_here   # Get free key at aistudio.google.com
APP_NAME="Open Demo Starter"
AI_CALLS_PER_USER_PER_DAY=50
AI_GLOBAL_TIMEOUT_SECONDS=15
```

---

## Authentication Security Patterns

### Password Reset — No User Enumeration

The forgot-password endpoint must return the same response whether or not the email exists:

```ruby
def create
  user = User.find_by(email: params[:email].downcase)
  if user
    token = SecureRandom.urlsafe_base64(32)
    user.password_resets.create!(token: token, expires_at: 30.minutes.from_now)
    PasswordMailer.reset(user, token).deliver_now
  end
  # Always redirect with the same message — never reveal whether email was found
  redirect_to sign_in_path, notice: "If that email is registered, you'll receive a reset link shortly."
end
```

### Admin Access — Return 404, Not 403

Returning 403 for admin routes reveals that the route exists. Return 404 instead:

```ruby
def require_admin
  unless current_user&.admin?
    render file: Rails.public_path.join("404.html"), status: :not_found
  end
end
```

---

## AI-Specific Security

These are handled by services, but understand the threat model:

| Risk | Mitigation | Service |
|---|---|---|
| Prompt injection | Regex pattern list, character limit | `AiGatekeeper` |
| Cost abuse | Daily call cap per user | `AiBudgetChecker` |
| Timeout / hanging | Hard timeout on API call | `GeminiService` |
| Cost visibility | Every call logged with token count + cost estimate | `LlmRequest` |

The gatekeeper checks happen **before** any API call — no credits or time consumed on blocked requests.

### What Is Deliberately Omitted

These are production-grade concerns that are out of scope for local demo apps:

- **PII scrubbing** — demo apps have no real user data; add Presidio in production
- **Content moderation API** — Gemini's built-in safety filters are sufficient here
- **Multi-provider fallback** — Gemini only; add redundancy in production
- **Automatic retries** — user clicks retry; avoids stacking costs on transient failures
- **Watermarking / fingerprinting** — not needed for single-user demo apps

---

## Pre-Launch Checklist (For Demo Apps)

Before pushing a new demo repo to GitHub:

- [ ] `git log --all -- .env` returns nothing
- [ ] No real API keys in any committed file (`git grep GEMINI_API_KEY`)
- [ ] `config/master.key` not tracked (`git ls-files config/master.key` returns nothing)
- [ ] `.env.example` has all required variables with placeholder values
- [ ] `db/seeds.rb` credentials are demo-only (`password123`, `demo@example.com`)
- [ ] No `binding.pry` or `debugger` in committed code
- [ ] No hardcoded app name, email, or personal info in views
- [ ] CSP initializer configured (at minimum `report_only = true`)
- [ ] Rate limiting on sign-in, sign-up, and password reset
- [ ] `reset_session` called before `session[:user_id] = user.id` on login
- [ ] AI disclaimer visible in footer on every page
