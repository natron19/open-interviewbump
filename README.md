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
| `APP_NAME` | `"Open Demo Starter"` | Displayed in the navbar and title |
| `APP_TAGLINE` | — | Shown in the footer |
| `APP_DESCRIPTION` | — | Shown on the landing page |
| `GEMINI_API_KEY` | (required) | Your Google Gemini API key — get one free at https://aistudio.google.com/app/apikey |
| `PERPLEXITY_API_KEY` | (required) | Your Perplexity API key — required for the agent's web search tool |
| `AI_CALLS_PER_USER_PER_DAY` | `50` | Daily AI call budget per user |
| `AI_GLOBAL_TIMEOUT_SECONDS` | `15` | Gemini request timeout in seconds |
| `AI_AGENT_TIMEOUT_SECONDS` | `45` | Per-round timeout for the multi-turn agent loop |

## Stack

| Layer | Choice |
|---|---|
| Framework | Rails 8.1 |
| Database | PostgreSQL with UUID primary keys |
| Auth | Rails native (`has_secure_password`, sessions) |
| CSS | Bootstrap 5 dark mode (CDN) |
| JavaScript | Stimulus + Turbo via importmap |
| AI | Google Gemini via `gemini-ai` gem |
| Queue / Cache / Cable | Solid Stack (no Redis) |
| Testing | RSpec |

## AI Safety Posture

**What this boilerplate enforces:**
- Per-user daily call cap (default: 50/day, set via `AI_CALLS_PER_USER_PER_DAY`)
- Pre-flight gatekeeper: input length limit, prompt injection patterns, profanity filter
- Hard output token cap per template
- Configurable request timeout (default: 15s)
- Full request log with status, tokens, duration, and cost estimate
- Fail-soft UI: errors render an inline alert, never crash the page
- AI disclaimer in the footer on every page

**Deliberately omitted (with rationale):**
- No PII scrubbing — demo apps have no production user data
- No content moderation API — Gemini's built-in safety filters are sufficient
- No automatic retries — avoids stacking costs on transient failures
- No RAG or vector DB — single-shot prompts only
- No streaming — synchronous calls keep the code simple

See `app/services/ai_gatekeeper.rb` and `app/services/ai_budget_checker.rb` to extend.

## Cost

All default templates use `gemini-2.5-flash`, which has a generous free tier. A user
running the demo locally will not incur charges under typical use.

## Customization

To build a new demo app on top of this boilerplate:

1. Update `APP_NAME`, `APP_TAGLINE`, `APP_DESCRIPTION` in `.env`
2. Set `--accent` color in `app/assets/stylesheets/application.css`
3. Replace `app/views/home/index.html.erb` with your landing page
4. Add your domain models, controllers, and views
5. Add your `AiTemplate` seeds in `db/seeds.rb`
6. Call `GeminiService.generate(template: "...", variables: {...})` from your controllers

Do not modify the auth system, admin panel, services, or layout for individual demo apps.

## License

MIT — see [LICENSE](LICENSE)
