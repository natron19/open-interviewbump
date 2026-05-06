# InterviewBump Demo — Build Tasks

**Spec:** `docs/open-interviewbump/interviewbump-demo-spec.md`
**Status tracking:** Check boxes as each item is completed. Complete all tasks in a phase, including tests, before starting the next phase.

---

## Architectural Notes (Read Before Starting)

### Model: `gemini-2.5-flash`
The spec lists `gemini-2.0-flash` for the AI template, but `docs/ai-templates.md` marks it deprecated for new API keys. Use `gemini-2.5-flash` throughout. The system prompt and output format are unchanged.

### CSS: No SCSS
The spec references `app/assets/stylesheets/_accent.scss`. Propshaft does not compile SCSS. All styles go directly in `app/assets/stylesheets/application.css`.

### `GeminiService.generate_with_tools`
This is the major new piece of infrastructure. The existing `GeminiService.generate` does one HTTP round-trip. The agent method runs a multi-turn loop using the Gemini function-calling API:

1. Send initial request with `tools: [{functionDeclarations: [...]}]`
2. If the response contains a `functionCall` part, dispatch the tool, collect the result, append it to `contents` as a `functionResponse` role message, and repeat
3. Stop when the response contains a text part OR after 5 rounds
4. Return `{text:, sources:, agent_trace:}` (a hash, not just a string)

The `search_web` and `fetch_url` tool implementations live in `PrepGuideJob`, not in `GeminiService`. Pass them as callable objects (procs or lambdas keyed by name) so the service stays generic. `generate_with_tools` accepts an `on_tool_call:` proc that the job passes in to trigger Turbo Stream broadcasts after each round.

### Turbo Stream Broadcasts from Solid Queue
Solid Queue workers run in the same process as the web server in development (`bin/dev` with Procfile). `ActionCable.server.broadcast` works fine for in-process jobs. Use `ActionCable.server.broadcast("prep_session_#{id}", {html: rendered_partial})` rather than `broadcast_update_to` (the latter requires Active Record model concerns not present on the boilerplate).

### Polling Pattern
The `prep_sessions#status` endpoint is a Turbo Stream response. The `polling` Stimulus controller drives the Turbo Frame src to `/prep_sessions/:id/status` every 3 seconds. When status becomes `complete` or `failed`, the controller stops updating the src. This avoids WebSockets complexity in favor of simple HTTP polling.

---

## Phase 0: Project Configuration ✅
*Estimated time: 30 min*

- [x] **0.1** Update `.env.example` with `APP_NAME`, `APP_TAGLINE`, `APP_DESCRIPTION`, `SERPER_API_KEY`
- [x] **0.2** Add accent and custom CSS to `app/assets/stylesheets/application.css` (green/purple, `.watch-out-callout`, `.agent-progress-feed`, `.prep-guide-accordion`)
- [x] **0.3** Update navbar: "My Sessions" → `prep_sessions_path`, "My Profile" → `edit_job_seeker_profile_path`
- [x] **Extra** Renamed all databases in `config/database.yml` from `open_base_*` to `open_interviewbump_*`; updated production username and password env var

**Phase 0 manual verification:**
- [ ] App boots (`bin/dev`) and existing pages work
- [ ] `demo@example.com / password123` sign-in works
- [ ] Navbar shows new links when signed in

---

## Phase 1: Data Model ✅
*Estimated time: 1 hr*

- [x] **1.1** `db/migrate/20260504000001_create_job_seeker_profiles.rb`
- [x] **1.2** `db/migrate/20260504000002_create_prep_sessions.rb`
- [x] **1.3** `db/migrate/20260504000003_create_prep_guides.rb`
- [x] **1.4** Run `rails db:migrate` ← **you must run this**
- [x] **1.5** `app/models/job_seeker_profile.rb`
- [x] **1.6** `app/models/prep_session.rb`
- [x] **1.7** `app/models/prep_guide.rb`
- [x] **1.8** `app/models/user.rb` updated with `has_one :job_seeker_profile` and `has_many :prep_sessions`
- [x] **1.9** `spec/factories/job_seeker_profiles.rb`
- [x] **1.10** `spec/factories/prep_sessions.rb`
- [x] **1.11** `spec/factories/prep_guides.rb`
- [x] **1.12** `spec/models/job_seeker_profile_spec.rb`
- [x] **1.13** `spec/models/prep_session_spec.rb`
- [x] **1.14** `spec/models/prep_guide_spec.rb`

**Phase 1 manual verification:**
- [ ] `rails db:migrate` runs without errors
- [ ] `rails db:rollback STEP=3 && rails db:migrate` round-trips cleanly
- [ ] Rails console: `JobSeekerProfile.create!(user: User.first, background_summary: "test")` succeeds
- [ ] Rails console: `User.first.prep_sessions.create!(job_title: "Engineer", company: "Stripe", status: "pending")` succeeds

**Phase 1 RSpec:** `bundle exec rspec spec/models/job_seeker_profile_spec.rb spec/models/prep_session_spec.rb spec/models/prep_guide_spec.rb`

**Phase 1 RSpec — run `bundle exec rspec spec/models/job_seeker_profile_spec.rb spec/models/prep_session_spec.rb spec/models/prep_guide_spec.rb`:**

Write `spec/models/job_seeker_profile_spec.rb`:
- [ ] Validates presence of `background_summary`
- [ ] Validates `background_summary` maximum length: exactly 2000 chars is valid; 2001 is not
- [ ] Validates presence of `user_id`
- [ ] `belongs_to :user` resolves correctly

Write `spec/models/prep_session_spec.rb`:
- [ ] Validates presence of `job_title`, `company`, `user_id`
- [ ] Validates `status` inclusion: accepts all four valid values; rejects arbitrary strings
- [ ] `belongs_to :user` resolves correctly
- [ ] `has_one :prep_guide` resolves correctly
- [ ] Destroying a `PrepSession` cascades to its `PrepGuide`

Write `spec/models/prep_guide_spec.rb`:
- [ ] Validates presence of `prep_session_id`
- [ ] `belongs_to :prep_session` resolves correctly
- [ ] `sources` and `agent_trace` stored as JSON round-trip through `JSON.parse` without error

---

## Phase 2: Routes ✅
*Estimated time: 15 min*

- [x] **2.1** `config/routes.rb` updated with `resource :job_seeker_profile` and `resources :prep_sessions` (with `member get :status`)
- [x] **2.2** Verify: `rails routes | grep prep_session` and `rails routes | grep job_seeker`

---

## Phase 3: Controllers and Basic Views ✅
*Estimated time: 2–3 hr*

- [x] **3.1** `app/controllers/job_seeker_profiles_controller.rb` (edit, update, strong params)
- [x] **3.2** `app/views/job_seeker_profiles/edit.html.erb` (form with character counter targets stubbed)
- [x] **3.3** `app/controllers/prep_sessions_controller.rb` (index, new, create, show, status, destroy, 404 scoping)
- [x] **3.4** `app/views/prep_sessions/index.html.erb` (table, status badge partial, empty state)
- [x] **3.5** `app/views/prep_sessions/_status_badge.html.erb`
- [x] **3.6** `app/views/prep_sessions/new.html.erb` (3-field form, profile warning)
- [x] **3.7** `app/views/prep_sessions/show.html.erb` (3-state conditional)
- [x] **3.8** `app/views/prep_sessions/_in_progress_state.html.erb`
- [x] **3.9** `app/views/prep_sessions/_failed_state.html.erb`
- [x] **3.10** `app/views/prep_sessions/_prep_guide.html.erb` (placeholder — full content in Phase 7)
- [x] **3.11** `app/controllers/dashboard_controller.rb` updated
- [x] **3.12** `app/views/dashboard/show.html.erb` replaced
- [x] **3.13** `app/jobs/prep_guide_job.rb` stub created (full implementation in Phase 6)
- [x] **3.14** `spec/requests/job_seeker_profiles_spec.rb`
- [x] **3.15** `spec/requests/prep_sessions_spec.rb`

**Phase 3 manual verification:**
- [ ] `rails db:migrate` (required before any of this works)
- [ ] Sign in, visit `/dashboard` — shows new layout with "New Prep Session" button
- [ ] Visit `/job_seeker_profile/edit`, enter background summary, click Save → redirects to dashboard with flash
- [ ] Visit `/prep_sessions/new`, fill job title and company, submit → creates session, redirects to show
- [ ] Show page renders in-progress state (spinner + turbo-frame)
- [ ] Visit `/prep_sessions`, see session in table with yellow "pending" badge
- [ ] Click delete → session removed, redirect to index with flash
- [ ] Visit another user's session URL → 404

**Phase 3 RSpec:** `bundle exec rspec spec/requests/job_seeker_profiles_spec.rb spec/requests/prep_sessions_spec.rb`

---

## Phase 4: Landing Page ✅
*Estimated time: 1 hr*

- [x] **4.1** Replace `app/views/home/index.html.erb` with:
  - **Hero section**: `APP_NAME` heading, `APP_TAGLINE` subheading, "Start preparing" CTA button to `sign_up_path`, secondary "Sign in" link to `sign_in_path`
  - **How it works**: Three-step Bootstrap grid with icon (or emoji), bold step title, one-line description per step: "Enter the job details", "Agent researches real candidate experiences", "Receive your personalized prep guide"
  - **Static sample prep guide accordion**: Bootstrap accordion with 2–3 static panels showing what the output looks like (hard-coded sample data for Stripe / Senior Software Engineer). Labels the accordion "Sample Prep Guide: Senior Software Engineer at Stripe". Includes at least one STAR outline panel and the watch-out callout. Does not render any dynamic data.
  - No Stimulus controllers or Turbo behavior on this page.

**Phase 4 manual verification:**
- [ ] Visit `/` while signed out — see all three sections
- [ ] Sample accordion opens and closes
- [ ] "Start preparing" links to sign up
- [ ] No JavaScript errors in browser console
- [ ] Page looks correct in dark mode with green accent buttons

---

## Phase 5: Stimulus Controllers ✅
*Estimated time: 1 hr*

### Character Counter
- [x] **5.1** Create `app/javascript/controllers/character_counter_controller.js`:
  - `static targets = ["input", "counter"]`
  - `static values = { max: { type: Number, default: 2000 } }`
  - `connect()`: call `update()`
  - `update()`: compute `remaining = maxValue - inputTarget.value.length`; update `counterTarget.textContent` with `${remaining} characters remaining`; toggle `text-danger` class on `counterTarget` when `remaining < 100`
  - Action: `input->character-counter#update` on the textarea

- [x] **5.2** Wire into `app/views/job_seeker_profiles/edit.html.erb`:
  - Wrap form in `data-controller="character-counter" data-character-counter-max-value="2000"`
  - Add `data-character-counter-target="input"` and `data-action="input->character-counter#update"` to the textarea
  - Add a `<small>` tag with `data-character-counter-target="counter"` below the textarea

### Polling Controller
- [x] **5.3** Create `app/javascript/controllers/polling_controller.js`:
  - `static values = { status: String, interval: { type: Number, default: 3000 } }`
  - `connect()`: if `statusValue` is not `"complete"` and not `"failed"`, start interval timer calling `this.poll()`
  - `poll()`: set `this.element.src` to the frame's current `src` (forces Turbo Frame refresh); after each poll, if `statusValue` becomes terminal, `clearInterval`
  - `statusValueChanged()`: if terminal status, `clearInterval` the polling timer
  - `disconnect()`: `clearInterval` the polling timer

- [x] **5.4** Wire into `app/views/prep_sessions/show.html.erb` in-progress state:
  - Add `data-controller="polling"` and `data-polling-status-value="<%= @prep_session.status %>"` to the `turbo_frame_tag`

**Phase 5 manual verification:**
- [ ] Visit `/job_seeker_profile/edit` — character counter shows "2000 characters remaining" on load
- [ ] Type in textarea — counter decrements in real time
- [ ] Type more than 1900 chars — counter text turns red
- [ ] Open browser DevTools console, verify no Stimulus errors on the show page for a pending session
- [ ] Verify polling controller connects (DevTools Stimulus inspector or console.log temporarily)

---

## Phase 6: Background Job & AI Integration ✅
*Estimated time: 4–6 hr — largest phase*

### GeminiService extension
- [x] **6.1** Add `self.generate_with_tools` to `GeminiService`:
  - Signature: `generate_with_tools(template:, variables:, tools:, user: Current.user, on_tool_call: nil)`
  - `tools` is a hash: `{ "search_web" => ->(args) { ... }, "fetch_url" => ->(args) { ... } }`
  - Runs gatekeeper, budget check, and creates the `LlmRequest` row exactly as `generate` does
  - Builds `tool_declarations` array from the tool hash keys (pass the JSON schema for each tool as a parameter alongside the lambda; define a `ToolDefinition` struct or use a simple `{name:, description:, parameters:, callable:}` hash)
  - Runs the agent loop (max 5 rounds):
    1. POST to Gemini with `tools: [{functionDeclarations: tool_declarations}]` and current `contents`
    2. If response part has `functionCall`: extract name + args, call the matching callable, push result into `contents` as `functionResponse`, call `on_tool_call` proc if provided, loop
    3. If response part has `text`: extract text, finish loop
    4. If 5 rounds reached without text: extract last text candidate or raise `GeminiError`
  - Accumulates `agent_trace` and `collected_sources` arrays internally
  - Returns `{ text: "...", sources: [...], agent_trace: [...] }` (a hash, not just a string)
  - Updates `LlmRequest` to `success` with token counts on completion; to `error`/`timeout` on failure

- [x] **6.2** Gemini function-calling request format (v1beta):
  ```json
  {
    "contents": [...],
    "tools": [{
      "functionDeclarations": [
        {
          "name": "search_web",
          "description": "Search the web and return top results.",
          "parameters": {
            "type": "OBJECT",
            "properties": {
              "query": { "type": "STRING", "description": "The search query" }
            },
            "required": ["query"]
          }
        }
      ]
    }],
    "generationConfig": { "maxOutputTokens": 3000, "temperature": 0.4 }
  }
  ```
  Function response format sent back to Gemini:
  ```json
  {
    "role": "function",
    "parts": [{
      "functionResponse": {
        "name": "search_web",
        "response": { "results": [...] }
      }
    }]
  }
  ```
  Note: the conversation `contents` array must track both the model's `functionCall` parts and the app's `functionResponse` parts in order.

### Tool Implementations
- [x] **6.3** Create `app/services/serper_search_service.rb` (or inline in the job as a private method):
  - Calls `https://google.serper.dev/search` with `Authorization: Bearer #{ENV.fetch("SERPER_API_KEY")}` header (or `X-API-KEY` header — check Serper docs)
  - POST body: `{ q: query, num: 5 }`
  - Returns array of `{ title:, url:, snippet: }` hashes from `organic` results
  - Raises `GeminiService::GeminiError` with message "SERPER_API_KEY missing or invalid" if key absent or request fails

- [x] **6.4** Implement `fetch_url` as a private method or inline callable:
  - HTTP GET to the URL using `Net::HTTP` or `Faraday` (15s timeout)
  - Strip HTML tags: `body.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip`
  - Truncate to 2500 characters
  - Returns the stripped text string
  - Adds URL to `collected_sources` (tracked in the job, passed via closure)
  - On connection error: returns `"[Could not fetch URL: #{url}]"` (do not raise; let the agent continue)

### PrepGuideJob
- [x] **6.5** Create `app/jobs/prep_guide_job.rb`:
  ```ruby
  class PrepGuideJob < ApplicationJob
    queue_as :default

    def perform(prep_session_id)
      prep_session = PrepSession.find(prep_session_id)
      user         = prep_session.user

      prep_session.update!(status: "researching")
      broadcast_status(prep_session, "Researching #{prep_session.company} interview experiences...")

      background_summary = user.job_seeker_profile&.background_summary.presence ||
                           "No background summary provided."
      job_desc_block     = prep_session.job_description.present? ?
                           "Job description:\n#{prep_session.job_description}" : ""

      collected_sources = []
      agent_trace       = []

      search_web_tool = {
        name: "search_web",
        description: "Search the web and return top results.",
        parameters: { type: "OBJECT", properties: { query: { type: "STRING" } }, required: ["query"] },
        callable: ->(args) {
          results = SerperSearchService.search(args["query"])
          preview = results.first(2).map { |r| "#{r[:title]} - #{r[:url]}" }.join("; ")
          agent_trace << { tool: "search_web", input: args["query"], result_preview: preview, timestamp: Time.current.iso8601 }
          broadcast_tool_call(prep_session, "search_web", args["query"])
          { results: results }
        }
      }

      fetch_url_tool = {
        name: "fetch_url",
        description: "Fetch the full text of a URL.",
        parameters: { type: "OBJECT", properties: { url: { type: "STRING" } }, required: ["url"] },
        callable: ->(args) {
          content = fetch_url_content(args["url"])
          collected_sources << args["url"]
          preview = content.first(200)
          agent_trace << { tool: "fetch_url", input: args["url"], result_preview: preview, timestamp: Time.current.iso8601 }
          broadcast_tool_call(prep_session, "fetch_url", args["url"])
          { content: content }
        }
      }

      Current.user = user
      result = GeminiService.generate_with_tools(
        template:  "interviewbump_prep_guide_v1",
        variables: {
          job_title:          prep_session.job_title,
          company:            prep_session.company,
          background_summary: background_summary,
          job_description:    job_desc_block
        },
        tools: { "search_web" => search_web_tool, "fetch_url" => fetch_url_tool },
        user: user
      )

      parsed = JSON.parse(result[:text].gsub(/\A```json\s*|\s*```\z/, ""))

      PrepGuide.create!(
        prep_session:     prep_session,
        likely_questions: parsed["likely_questions"].to_json,
        star_outlines:    parsed["star_outlines"].to_json,
        questions_to_ask: parsed["questions_to_ask"].to_json,
        watch_out:        parsed["watch_out"],
        company_signals:  parsed["company_signals"].to_json,
        sources:          collected_sources.to_json,
        agent_trace:      agent_trace.to_json,
        gemini_raw:       result[:text]
      )

      prep_session.update!(status: "complete")
      broadcast_complete(prep_session)

    rescue GeminiService::GeminiError => e
      prep_session.update!(status: "failed", error_message: e.message)
      broadcast_failed(prep_session)
    rescue JSON::ParserError => e
      prep_session.update!(status: "failed", error_message: "Failed to parse AI response: #{e.message.truncate(200)}")
      broadcast_failed(prep_session)
    ensure
      Current.user = nil
    end

    private

    def fetch_url_content(url)
      uri      = URI.parse(url)
      response = Net::HTTP.get_response(uri)
      body     = response.body.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      stripped = body.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
      stripped.first(2500)
    rescue => e
      "[Could not fetch URL: #{e.message}]"
    end

    def broadcast_status(prep_session, message)
      html = ApplicationController.render(
        partial: "prep_sessions/progress_status",
        locals:  { message: message, agent_trace: [] }
      )
      ActionCable.server.broadcast("prep_session_#{prep_session.id}", { html: html })
    end

    def broadcast_tool_call(prep_session, tool, input)
      html = ApplicationController.render(
        partial: "prep_sessions/progress_tool_call",
        locals:  { tool: tool, input: input.truncate(80) }
      )
      ActionCable.server.broadcast("prep_session_#{prep_session.id}", { html: html })
    end

    def broadcast_complete(prep_session)
      ActionCable.server.broadcast("prep_session_#{prep_session.id}", { status: "complete" })
    end

    def broadcast_failed(prep_session)
      ActionCable.server.broadcast("prep_session_#{prep_session.id}", { status: "failed" })
    end
  end
  ```
  Note: The `broadcast_status` / `broadcast_tool_call` approaches use `ApplicationController.render` to generate partial HTML for the progress feed. The polling approach (`status` endpoint) re-fetches current state on each tick rather than relying on push, so these broadcasts can be simplified or removed; implement whichever feels cleaner after testing. The polling approach is more reliable with Solid Queue.

- [x] **6.6** Update `PrepSessionsController#create` to enqueue `PrepGuideJob.perform_later(@prep_session.id)` after saving

- [x] **6.7** Implement `PrepSessionsController#status` (HTML format, renders `status.html.erb` with turbo-frame wrapper — polling controller uses frame src reload):
  - Loads `@prep_session` (already set by `before_action`)
  - Responds with `format.turbo_stream`:
    - If `complete`: `turbo_stream.update("prep-guide-status") { render partial: "prep_sessions/prep_guide", locals: { prep_guide: @prep_session.prep_guide, prep_session: @prep_session } }`
    - If `failed`: `turbo_stream.update("prep-guide-status") { render partial: "prep_sessions/failed_state", locals: { prep_session: @prep_session } }`
    - If `pending`/`researching`: `turbo_stream.update("prep-guide-status") { render partial: "prep_sessions/in_progress_state", locals: { prep_session: @prep_session } }`

- [x] **6.8** Add AI template seed to `db/seeds.rb` (`interviewbump_prep_guide_v1` — full system prompt and user prompt template from spec Section 7; model: `gemini-2.5-flash`, max_output_tokens: 3000, temperature: 0.4)

- [ ] **6.9** Run `rails db:seed` ← **you must run this**

**Phase 6 manual verification:**
- [ ] Create a prep session with a real `GEMINI_API_KEY` and `SERPER_API_KEY`
- [ ] Show page updates every 3 seconds during processing
- [ ] Progress area shows each tool call ("search_web: Stripe Senior Software Engineer interview site:reddit.com")
- [ ] On completion, page transitions to showing a complete state (full partial comes in Phase 7)
- [ ] Admin → LLM Requests shows the completed call
- [ ] Test failure path: temporarily use an invalid `SERPER_API_KEY`; session transitions to failed state with error message

**Phase 6 RSpec — add to existing files or create `spec/jobs/prep_guide_job_spec.rb`:**
- [ ] When stub returns valid JSON: creates `PrepGuide` with all fields populated and non-nil
- [ ] Updates `PrepSession#status` to `"complete"` on success
- [ ] Updates `PrepSession#status` to `"failed"` when `GeminiService::GeminiError` raised; `error_message` populated
- [ ] `agent_trace` is a non-empty JSON array after a successful run (stub provides tool call trace)
- [ ] `sources` on the created `PrepGuide` is a non-empty JSON array after a successful run
- [ ] Update `spec/requests/prep_sessions_spec.rb`: `POST /prep_sessions` with valid params enqueues `PrepGuideJob` (use `have_enqueued_job(PrepGuideJob)` matcher)

---

## Phase 7: Prep Guide Display ✅
*Estimated time: 2 hr*

- [x] **7.1** Create `app/views/prep_sessions/_prep_guide.html.erb`:
  - Page heading: "Prep Guide: [job_title] at [company]"
  - Inline disclaimer callout (Bootstrap `alert-info` or custom card): per spec Section 6
  - Bootstrap accordion with CSS class `prep-guide-accordion`, `id="questions-accordion"`:
    - 5 panels, each with `id="question-N"`, `data-bs-parent="#questions-accordion"`
    - Panel header: question text
    - Panel body: labeled Situation / Task / Action / Result fields from `star_outlines` JSON
    - Parse `JSON.parse(prep_guide.star_outlines)` and `JSON.parse(prep_guide.likely_questions)` at top of partial
  - "Company-specific signals" section: `h5` heading, `ul` with 2 items from `JSON.parse(prep_guide.company_signals)`
  - "Smart questions to ask" section: `h5` heading, `ol` with 3 items from `JSON.parse(prep_guide.questions_to_ask)`
  - Watch-out callout: `div.watch-out-callout` with bold "Watch out:" prefix and `prep_guide.watch_out` text
  - "Sources the agent consulted" Bootstrap collapse section: toggle button + collapsible `ul` with clickable `<a target="_blank">` links from `JSON.parse(prep_guide.sources)`
  - "Show raw response" Bootstrap collapse toggle + `<pre>` block with `prep_guide.gemini_raw`
  - Back link to `prep_sessions_path`

- [x] **7.2** `app/views/prep_sessions/_in_progress_state.html.erb` (already implemented in Phase 3):
  - Spinner (Bootstrap `spinner-border` in `#7c3aed` purple inline style or custom class)
  - Status text: "Researching [company] interview experiences..."
  - Agent progress feed: `div.agent-progress-feed` showing the most recent tool call from `@prep_session` (store last broadcast message, or just show "Working..." as placeholder — real-time updates via polling are sufficient)

- [x] **7.3** `app/views/prep_sessions/_failed_state.html.erb` (updated with terminalStatus target):
  - Bootstrap `alert-danger` with `@prep_session.error_message`
  - "Try again" button: link to `new_prep_session_path(job_title: prep_session.job_title, company: prep_session.company)`

- [x] **7.4** `app/views/prep_sessions/show.html.erb` (already using three partials; status.html.erb created for Turbo Frame polling)

- [x] **7.5** `app/views/prep_sessions/new.html.erb` already pre-fills from params (done in Phase 3)

**Phase 7 manual verification:**
- [ ] Generate a real prep guide, verify all 5 question panels render with STAR outlines
- [ ] Each accordion panel expands on click, highlights in green when open
- [ ] Company signals, questions to ask, and watch-out sections all render
- [ ] Sources links are clickable (external links, `target="_blank"`)
- [ ] "Show raw response" toggle reveals the JSON blob in a `<pre>` block
- [ ] Watch-out callout has purple left border
- [ ] Failed state: retry button pre-fills job title and company in the new session form
- [ ] Delete from sessions index removes both the session and its prep guide

---

## Phase 8: Seed Data ✅
*Estimated time: 1 hr*

- [x] **8.1** Add `JobSeekerProfile` seed for `demo@example.com` user (background_summary from spec Section 10)
- [x] **8.2** Add completed `PrepSession` seed: "Senior Software Engineer" at "Stripe", `status: "complete"`, with associated `PrepGuide` (realistic sample content from spec Section 10)
- [x] **8.3** Add in-progress `PrepSession` seed: "Backend Engineer" at "Notion", `status: "pending"`, no `PrepGuide`
- [x] **8.4** `demo_placeholder_v1` removed from seeds — InterviewBump uses `interviewbump_prep_guide_v1` exclusively
- [ ] **8.5** Run `rails db:seed` ← **you must run this**

**Phase 8 manual verification:**
- [ ] `rails db:seed` runs without errors from a fresh or existing database
- [ ] Sign in as `demo@example.com`, dashboard shows two recent sessions
- [ ] Stripe session shows full prep guide with all sections populated with realistic data
- [ ] Notion session shows in-progress (pending) state
- [ ] Admin → AI Templates shows `interviewbump_prep_guide_v1` with correct model, temperature, and token limit

---

## Phase 9: Full RSpec Suite & Final Verification
*Estimated time: 2 hr*

- [ ] **9.1** Confirm `spec/support/rate_limit_helpers.rb` is in place (prevents rate limit cascade failures)
- [x] **9.2** `spec/requests/prep_sessions_spec.rb` covers the job enqueue assertion (Phase 6)
- [x] **9.3** Run full suite: `bundle exec rspec --format documentation` — all 112 examples pass ✅
- [x] **9.4** Zero real Gemini API calls in test output (all stubs)
- [x] **9.5** All specs pass ✅

**Notes on spec changes made during Phase 9:**
- Rewrote model specs to not require `shoulda-matchers` (not in Gemfile) — used `reflect_on_association` and explicit `be_valid` checks
- Fixed FactoryBot 6 build strategy: `build(:model)` also builds associations (leaving `user_id: nil`); specs now pass `user: create(:user)` explicitly
- Fixed index spec: both sessions used factory default `"Acme Corp"` — now use distinct company names
- Updated show spec: `"Prep guide ready"` was the Phase 3 placeholder; now asserts `"Likely Interview Questions"` from the full Phase 7 partial

**Full end-to-end manual test:**
- [ ] Sign up as a brand-new user (not demo@example.com)
- [ ] See profile prompt on dashboard
- [ ] Add background summary; character counter works; save redirects to dashboard; profile prompt gone
- [ ] Click "New Prep Session", fill in real company/role, submit
- [ ] Watch show page poll every 3 seconds; progress feed updates with tool calls
- [ ] Prep guide renders with all sections on completion
- [ ] Delete the session; redirects to index; session gone
- [ ] Sign out, sign back in, dashboard empty
- [ ] Admin panel (sign in as demo@example.com): LLM Requests log shows all calls; AI Templates shows template; test panel runs the template live

---

## Known Constraints & Decisions

| Item | Decision |
|---|---|
| Model name | Use `gemini-2.5-flash` (not `gemini-2.0-flash` — deprecated per docs) |
| CSS compilation | All styles in `application.css` (no SCSS, Propshaft only) |
| Polling vs. WebSockets | HTTP polling every 3s via `polling` Stimulus controller + `status` endpoint |
| Agent broadcast | Polling re-reads DB state each tick; ActionCable broadcasts are additive visual feedback only |
| `job_description` rendering | Conditional in job before passing to `GeminiService` — omit blank, prepend "Job description:\n" if present |
| `generate_with_tools` return type | Returns `{text:, sources:, agent_trace:}` hash (different from `generate` which returns string) |
| JSON strip | Gemini sometimes wraps JSON in `` ```json ``` `` fences — strip before `JSON.parse` |
| Serper API auth | Use `X-API-KEY` header (Serper v2 format); check Serper docs if requests fail |

---

*Last updated: 2026-05-04. All 9 phases implemented. RSpec suite passes (112 examples, 0 failures). Remaining: Phase 9 manual end-to-end test and `rails db:seed`.*
