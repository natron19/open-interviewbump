# Phase 7 — Seed Data, CI & Final Packaging

**Goal:** A fresh clone can be set up and running in under 30 minutes. CI passes. The repo is clean with zero secrets.

**Depends on:** Phases 1–6 complete

---

## 1. `db/seeds.rb`

```ruby
# Admin user — credentials for local demo use only
User.find_or_create_by!(email: "demo@example.com") do |u|
  u.name                  = "Demo User"
  u.password              = "password123"
  u.password_confirmation = "password123"
  u.admin                 = true
end

puts "Demo user created: demo@example.com / password123"

# Health ping template — used by /up/llm
AiTemplate.find_or_create_by!(name: "health_ping") do |t|
  t.description          = "Minimal prompt used by the /up/llm health check endpoint."
  t.system_prompt        = "You are a health check endpoint. Respond with exactly: ok"
  t.user_prompt_template = "ping"
  t.model                = "gemini-2.0-flash"
  t.max_output_tokens    = 10
  t.temperature          = 0.0
  t.notes                = "Do not modify. Used by HealthController#llm."
end

puts "Seeded: health_ping AI template"

# Placeholder demo template — each demo app replaces this
AiTemplate.find_or_create_by!(name: "demo_placeholder_v1") do |t|
  t.description          = "Starter template. Replace with your demo's actual prompt."
  t.system_prompt        = "You are a helpful assistant."
  t.user_prompt_template = "Please help me with: {{request}}"
  t.model                = "gemini-2.0-flash"
  t.max_output_tokens    = 2000
  t.temperature          = 0.7
  t.notes                = "Starter template. Replace this in your demo app's seeds.rb."
end

puts "Seeded: demo_placeholder_v1 AI template"
```

---

## 2. `bin/setup`

```bash
#!/usr/bin/env bash
set -e

echo "== Installing dependencies =="
bundle install

echo "== Copying .env.example to .env =="
if [ ! -f .env ]; then
  cp .env.example .env
  echo "   .env created. Add your GEMINI_API_KEY before starting the server."
else
  echo "   .env already exists, skipping."
fi

echo "== Creating and migrating database =="
bundle exec rails db:create db:migrate

echo "== Seeding demo data =="
bundle exec rails db:seed

echo ""
echo "== Setup complete =="
echo ""
echo "  Start the server:  bin/rails server"
echo "  Sign in at:        http://localhost:3000/sign_in"
echo "  Demo credentials:  demo@example.com / password123"
echo "  Admin panel:       http://localhost:3000/admin"
echo ""
echo "  Don't forget: set GEMINI_API_KEY in your .env"
echo ""
```

Make executable: `chmod +x bin/setup`

---

## 3. `.env.example` (final version)

Ensure all env vars are documented with inline comments:

```bash
# ── App Branding ───────────────────────────────────────────────────────────────
APP_NAME="Open Demo Starter"
APP_TAGLINE="A minimal Rails 8 + AI boilerplate"
APP_DESCRIPTION="Clone, run, and extend in under 30 minutes."

# ── Database ───────────────────────────────────────────────────────────────────
# DATABASE_URL=postgres://localhost/open_base_development  # optional override

# ── Google Gemini ──────────────────────────────────────────────────────────────
# Get your free API key at https://makersuite.google.com/app/apikey
GEMINI_API_KEY=your_gemini_api_key_here

# ── AI Operational Limits ──────────────────────────────────────────────────────
AI_CALLS_PER_USER_PER_DAY=50
AI_GLOBAL_TIMEOUT_SECONDS=15
```

---

## 4. `.gitignore` (final audit)

Ensure these are present:

```
# Secrets — never commit these
.env
*.env.local
.env.*.local

# Rails defaults
/log/*
/tmp/*
!/log/.keep
!/tmp/.keep
/storage/*
!/storage/.keep
/public/assets
.byebug_history
.DS_Store
```

Verify:
- `.env.example` is NOT in `.gitignore` (it must be committed)
- `config/credentials.yml.enc` is NOT exposed
- `config/master.key` IS in `.gitignore` (Rails default)

---

## 5. `LICENSE`

MIT License file at repo root:

```
MIT License

Copyright (c) 2026 [Your GitHub Handle]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 6. `README.md`

Structure:

```markdown
# Open Demo Starter

> A minimal Rails 8 + AI boilerplate for single-purpose demo apps.

## Quick Start

1. Clone this repo
2. Run `bin/setup`
3. Add your Gemini API key to `.env`
4. `bin/rails server`
5. Visit http://localhost:3000 and sign in with `demo@example.com` / `password123`

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `APP_NAME` | "Open Demo Starter" | Displayed in the navbar and title |
| `APP_TAGLINE` | — | Shown in the footer |
| `APP_DESCRIPTION` | — | Shown on the landing page |
| `GEMINI_API_KEY` | (required) | Your Google Gemini API key |
| `AI_CALLS_PER_USER_PER_DAY` | 50 | Daily AI call budget per user |
| `AI_GLOBAL_TIMEOUT_SECONDS` | 15 | Gemini request timeout |

## Stack

Rails 8 · PostgreSQL · Bootstrap 5 (dark) · Stimulus · Turbo · Gemini

## AI Safety Posture

**What this boilerplate enforces:**
- Per-user daily call cap (default: 50/day)
- Pre-flight gatekeeper: input length, prompt injection patterns, profanity
- Hard output token cap per template
- 15-second request timeout
- Full request log with status, tokens, duration, cost estimate
- Fail-soft UI: errors render an inline alert, never crash the page
- AI disclaimer in the footer on every page

**Deliberately omitted (with rationale):**
- No PII scrubbing — demo apps have no production user data
- No content moderation API call — Gemini's safety filters are sufficient here
- No automatic retries — avoids stacking costs on transient failures
- No RAG or vector DB — single-shot prompts only
- No streaming — synchronous calls keep the app simple

See `app/services/ai_gatekeeper.rb` and `app/services/ai_budget_checker.rb` to extend.

## Cost

All templates use `gemini-2.0-flash`. A user running the demo locally under the free tier
will not be charged for typical use.

## Customization (for demo apps)

1. Update `APP_NAME`, `APP_TAGLINE`, `APP_DESCRIPTION` in `.env`
2. Set `--accent` in `app/assets/stylesheets/application.css`
3. Replace `app/views/home/index.html.erb`
4. Add your domain models, controllers, and views
5. Add your `AiTemplate` seeds
6. Wire your controller to `GeminiService.generate(template: "...", variables: {...})`

## License

MIT — see [LICENSE](LICENSE)
```

---

## 7. GitHub Actions CI (Final)

File: `.github/workflows/ci.yml` — as specified in Phase 6.

Verify the workflow:
- Runs on push to `master` and on pull requests
- Uses PostgreSQL service container
- Sets `GEMINI_API_KEY=not_a_real_key` (tests use the stub, not the real API)
- Runs `db:create db:schema:load` (not `db:migrate`) for speed
- Runs `bundle exec rspec`

---

## 8. Final Security Audit

Before tagging `v2.0.0`, verify:

- [ ] `git log --all -- .env` — no `.env` file has ever been committed
- [ ] `git grep "GEMINI_API_KEY" -- ":(exclude).env.example"` — no real key in source
- [ ] `git grep "password123"` — only appears in `seeds.rb` and `README.md` (demo credentials only)
- [ ] `config/master.key` is in `.gitignore` and NOT tracked
- [ ] No `binding.pry` or `byebug` calls in production code paths
- [ ] No hardcoded IP addresses, internal URLs, or personal email addresses in source

---

## 9. Git Tag

After all specs pass and the security audit is clean:

```bash
git tag -a v2.0.0 -m "Open Demo Starter v2.0.0 — Rails 8, Gemini, admin panel, guardrails"
git push origin v2.0.0
```

---

## Acceptance Criteria

- [ ] `git clone <repo> && cd <repo> && bin/setup` completes without errors on a clean machine
- [ ] `bin/rails server` starts; visiting `http://localhost:3000` shows the landing page
- [ ] Signing in with `demo@example.com` / `password123` works
- [ ] Admin panel at `/admin` is accessible with the seeded user
- [ ] `GET /up/llm` returns `{"status":"ok"}` with a real API key set
- [ ] `bundle exec rspec` passes with no failures
- [ ] GitHub Actions CI passes on push
- [ ] No real secrets in any committed file
- [ ] `LICENSE` file is present at repo root
- [ ] `README.md` includes Quick Start, env var table, AI safety posture, and cost sections
- [ ] `.env.example` has all vars documented with comments; no real values
- [ ] Repo is tagged `v2.0.0`
