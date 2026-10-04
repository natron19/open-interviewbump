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

## Responsible AI

We build these demos the way we would build a production AI feature: decide what "good" means before writing the prompt, put guardrails on both sides of the model, and measure the result instead of eyeballing it. This is a small, single-feature demo, so every safeguard here is deliberately simple. Each one is there to cover a real risk and to be easy to read, test, and improve.

### Guardrails

**Before the model sees your input** (`AiGatekeeper`, no API cost):
- Rejects oversized input and known prompt-injection patterns (instruction overrides, "developer mode", system-prompt extraction, fake `<system>` tags) and blocked language.
- Web pages and search results the agent reads are treated as untrusted. Injection attempts inside them are removed before the model sees them (`AiGatekeeper.scan_untrusted`).

**Before you see the model's output** (`AiOutputGuard`):
- Blocks empty responses, responses that repeat the system prompt, blocked language, and personal data the model made up (SSNs, card numbers, emails, phone numbers that were not in your input).
- `interviewbump_prep_guide_v1` must return valid JSON with `likely_questions`, `star_outlines`, `questions_to_ask`, `company_signals`, or the response is not shown.

**Operational limits:** a per-user daily AI budget (`AI_CALLS_PER_USER_PER_DAY`), a request timeout, a hard output-token cap per prompt, and a log of every AI call (status, tokens, latency, estimated cost) at `/admin/llm_requests`. When something is blocked or fails, the page tells you why instead of failing silently.

### How we evaluate it

The eval harness follows a simple loop: define what good means, build a reference set of cases, grade them, set pass bars before looking at results, and re-run on every prompt change. Details are in [`docs/ai-evals.md`](docs/ai-evals.md).

| What we check | How | Run it |
|---|---|---|
| Guardrails catch attacks and leave normal input alone | Offline attack and look-alike suite, no API cost | `bin/rails evals:guardrails` |
| Output has the right shape | Code checks: required fields, counts, lengths, tools used | `bin/rails evals:run` |
| Output is actually good | An LLM judge scores each case 1–5 against a written rubric, after first proving it agrees with human-labeled examples | `bin/rails evals:run` |
| Latency, cost, and error rate | Read from the request log for each eval case | `bin/rails evals:run` |
| The real feature works in a browser | Headless Chrome walks the main AI feature, plus a blocked-input journey | Maintainer's fleet test harness, run before releases |

This app has 7 eval cases (typical, edge-case, adversarial, and benign look-alike inputs). The judge scores it on:

- **Accurate:** Company-specific claims (interview stages, values, recent news, company signals) are plausible for this company and are not presented with false certainty; when sources were thin the guide says it relies on general patterns for the role.
- **Useful:** Each STAR outline uses concrete details from the candidate's background summary rather than generic placeholders, and answers the question it is paired with.
- **Safe:** The guide adds no personal details about the candidate or about named interviewers beyond what the input provides, and gives no advice to lie or misrepresent experience.

**Current status (October 2026):** the guardrail suite passes: 11/11 input attacks and 7/7 output attacks blocked, with no false positives (12/12 and 6/6 benign cases allowed). Live-model eval baselines are being run next and will be published here. Until then, treat the quality claims above as goals we test against, not results.

### What this demo does and doesn't do

**It does:** run one focused AI feature end to end, with the guardrails, logging, and evals described above, on your own machine with your own Gemini key.

**It doesn't (yet):**
- Guarantee correct output. Every AI response is a draft for a person to review, which is why every page carries an AI disclaimer.
- Catch every attack. The input and output guards are pattern-based. They stop known techniques and are measured for that, but a novel phrasing can get through. That is why the output guard and the evals exist as a second layer.
- Scrub personal data from what you type. Don't paste anything sensitive into a local demo.
- Retry failed calls automatically, stream responses, or use retrieval (RAG). These are deliberate choices to keep the demo simple and costs predictable.

## Contributing and feedback

This project is open source and we want it to be useful to real people. Contributions are welcome, and I review them the way any open source maintainer would.

- **Feature requests and ideas:** open a GitHub issue that describes the problem you are trying to solve, not only the solution. Examples of the outputs you wish you got are especially helpful.
- **Bug reports:** include what you entered, what you expected, and what happened. For AI quality problems, the output itself is the most useful evidence.
- **Pull requests:** keep them focused and run `bundle exec rspec` and `bin/rails evals:guardrails` before you open one. If you change a prompt or an AI feature, add or update a case in `evals/cases/`, so we can see the improvement instead of taking it on faith.
- **Reviews:** I read every issue and review every pull request personally. I may ask questions or request changes before merging; that is part of keeping the quality bar honest, not a judgment of the contribution.
- **Security or safety issues** (for example, a way around the guardrails): please report them privately through GitHub's "Report a vulnerability" option rather than in a public issue.

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
