# InterviewBump Demo - Spec Document

**Document Version:** 1.0
**Last Updated:** May 1, 2026
**Built On:** Open Demo Starter v2.0
**License:** MIT

---

## 1. App Overview

InterviewBump Demo isolates the core value of the InterviewBump SaaS product: researching how a specific company actually interviews for a specific role and building a personalized prep guide from that intelligence.

The user enters a job title, company name, and a brief background summary. A Gemini agent runs targeted web searches on Reddit and Glassdoor to gather real candidate experiences, fetches the most relevant result it finds, and synthesizes everything into a structured prep guide. The guide includes the 5 most likely questions for this company and role (drawn from what real candidates report, not generic lists), a STAR-format answer outline for each tailored to the user's background, 2 company-specific signals to reference that demonstrate genuine research, 3 smart questions to ask the interviewer, and one watch-out pattern that catches candidates off guard at this specific company.

Generic interview prep is a solved problem. What is hard is knowing how THIS company specifically interviews for THIS role. Real candidates post their experiences publicly on Reddit and Glassdoor; the agent finds and synthesizes that intelligence so the user walks in with company-specific expectations rather than generic STAR framework knowledge. That specificity is the differentiator over every "tell me about yourself" prep guide that already exists.

This is a demo of one feature from InterviewBump, a multi-tenant SaaS tool for individual contributors and small teams preparing for technical and behavioral interviews. The production version adds team workspaces, manager-assigned prep sessions, prep history across organizations, and collaborative review flows. This demo is scoped to a single signed-in user, runs locally, and is open source under the MIT license.

---

## 2. Customizations Applied to the Boilerplate

- `APP_NAME=InterviewBump Demo`, `APP_TAGLINE=Tell it the company and role. The agent researches real interview experiences and builds your prep guide.`, `APP_DESCRIPTION=AI-powered interview prep that researches how this specific company actually interviews for this role.` set in `.env.example`
- Accent color `#16a34a` (green) and hover `#0f9a34` set in `app/assets/stylesheets/_accent.scss`; secondary accent `#7c3aed` (purple) used for agent progress feed and watch-out callout styling
- Navbar links: "My Sessions" links to `/prep_sessions`; "My Profile" links to `/job_seeker_profile/edit`
- `home/index.html.erb` replaced with a landing page showing a three-step how-it-works flow, a static sample prep guide accordion so visitors see what output looks like before signing up, and a sign-up call to action
- `dashboard/show.html.erb` replaced with a summary of the user's 5 most recent prep sessions and a "New Prep Session" primary button
- UX pattern: form-then-agent-progress. The user fills a short form, submits it, the page transitions to a Turbo Stream progress feed while the agent runs, and the final output renders as a Bootstrap accordion
- AI templates seeded: `interviewbump_prep_guide_v1`
- Additional env var: `SERPER_API_KEY` for the Serper.dev web search integration (required; see Section 11 for setup)

---

## 3. Data Model

### JobSeekerProfile

Stores the user's background summary. One record per user. Used as context in every prep guide generation.

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | Primary key |
| `user_id` | uuid | Foreign key |
| `background_summary` | text | **(template variable)** Brief description of the user's experience, skills, and career focus. Maximum 2000 characters. |
| `created_at` | datetime | |
| `updated_at` | datetime | |

**Associations:** `belongs_to :user`; `User has_one :job_seeker_profile`

**Validations:** `user_id` presence; `background_summary` presence, maximum length 2000

---

### PrepSession

Represents one interview prep request. Stores the job details the user entered and the current agent status.

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | Primary key |
| `user_id` | uuid | Foreign key |
| `job_title` | string | **(template variable)** The role the user is preparing for |
| `company` | string | **(template variable)** The company conducting the interview |
| `job_description` | text | Optional. User-pasted job posting for additional context. **(template variable)** Omitted from prompt if blank. |
| `status` | string | `pending`, `researching`, `complete`, `failed`. Drives the Turbo Stream progress UI. |
| `error_message` | text | Populated on `failed`. Shown in the error partial. |
| `created_at` | datetime | |
| `updated_at` | datetime | |

**Associations:** `belongs_to :user`; `has_one :prep_guide, dependent: :destroy`

**Validations:** `user_id`, `job_title`, `company` presence; `status` inclusion in `["pending", "researching", "complete", "failed"]`

---

### PrepGuide

Stores the structured output from the agent. Created when the agent completes successfully.

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | Primary key |
| `prep_session_id` | uuid | Foreign key |
| `likely_questions` | text | JSON array of 5 question strings |
| `star_outlines` | text | JSON array of STAR objects, one per question: `{question, situation, task, action, result}`, tailored to the user's background |
| `questions_to_ask` | text | JSON array of 3 question strings for the interviewer |
| `watch_out` | text | Plain text. One pattern in this company's interviews that catches candidates off guard. |
| `company_signals` | text | JSON array of 2 company-specific talking points to reference in the interview |
| `sources` | text | JSON array of URL strings: the pages the agent fetched during research |
| `agent_trace` | text | JSON array of tool call records: `{tool, input, result_preview, timestamp}`. Stored for admin inspection. |
| `gemini_raw` | text | **(Gemini output, used for Show raw response toggle)** Full raw text returned by the final synthesis call |
| `created_at` | datetime | |
| `updated_at` | datetime | |

**Associations:** `belongs_to :prep_session`; `PrepSession has_one :prep_guide`

**Validations:** `prep_session_id` presence

---

## 4. Routes

| HTTP Verb | Path | Controller#Action | Purpose |
|---|---|---|---|
| GET | `/` | `home#index` | Public landing page |
| GET | `/dashboard` | `dashboard#show` | Logged-in home; shows recent prep sessions |
| GET | `/job_seeker_profile/edit` | `job_seeker_profiles#edit` | Edit background summary form |
| PATCH | `/job_seeker_profile` | `job_seeker_profiles#update` | Save background summary |
| GET | `/prep_sessions` | `prep_sessions#index` | List user's past sessions |
| GET | `/prep_sessions/new` | `prep_sessions#new` | New prep session form |
| POST | `/prep_sessions` | `prep_sessions#create` | Submit job details; enqueue agent job |
| GET | `/prep_sessions/:id` | `prep_sessions#show` | Show prep session; renders progress or prep guide |
| GET | `/prep_sessions/:id/status` | `prep_sessions#status` | Turbo Stream polling endpoint for in-progress sessions |
| DELETE | `/prep_sessions/:id` | `prep_sessions#destroy` | Delete session and its prep guide |

---

## 5. Controllers and Actions

### `JobSeekerProfilesController`

- **`edit`**: Finds or initializes the `JobSeekerProfile` for `current_user`. Renders the background summary form.
- **`update`**: Upserts the `JobSeekerProfile` for `current_user` with validated params. Redirects to dashboard on success with a flash notice. Re-renders `edit` on validation failure.

---

### `PrepSessionsController`

- **`index`**: Loads `current_user.prep_sessions.order(created_at: :desc).includes(:prep_guide)`. Renders the session list with status badges.

- **`new`**: Instantiates a blank `PrepSession`. Renders the job details form. If the user has no `JobSeekerProfile` with a `background_summary`, renders an inline Bootstrap alert prompting them to complete their profile first, with a link to `job_seeker_profiles#edit`.

- **`create`**: Creates a `PrepSession` with `status: "pending"`, then enqueues `PrepGuideJob` with the session ID. Redirects to `prep_sessions#show` for the new session. The actual `GeminiService.generate_with_tools` call happens in the job, not in this action.

- **`show`**: Loads the `PrepSession` and its `PrepGuide` if present. Renders one of three states based on `status`: in-progress (Turbo Frame polling), complete (prep guide accordion), or failed (error partial with retry button).

- **`status`**: Lightweight polling endpoint. Returns a Turbo Stream `update` to the `prep-guide-status` frame. If `status: "complete"`, the update renders the prep guide partial. If `status: "failed"`, the update renders the error partial. If still in progress, the update refreshes the spinner text. Called by the Turbo Frame's polling interval.

- **`destroy`**: Destroys the `PrepSession` (cascades to `PrepGuide`). Redirects to `prep_sessions#index`.

---

### `PrepGuideJob` (Solid Queue job)

Handles the agent loop. Enqueued by `PrepSessionsController#create`.

1. Updates `PrepSession#status` to `"researching"` and broadcasts the status change via Turbo Streams.
2. Assembles variables: `job_title`, `company`, `job_description` from the session; `background_summary` from the user's `JobSeekerProfile`.
3. Calls `GeminiService.generate_with_tools(template: "interviewbump_prep_guide_v1", variables: {...}, tools: [search_web_tool, fetch_url_tool])`.
4. As each tool call completes, broadcasts a Turbo Stream update to the show page's progress feed.
5. On success, parses the JSON response, creates a `PrepGuide` record with all fields, and updates `PrepSession#status` to `"complete"`.
6. On any `GeminiService::GeminiError`, updates `PrepSession#status` to `"failed"` and stores the error message in `PrepSession#error_message`.

---

## 6. Views

### `home/index.html.erb`

Replaces the boilerplate placeholder. Static marketing page with:
- Hero section with app name, tagline, and a "Start preparing" call to action linking to sign-up.
- A three-step how-it-works flow using Bootstrap icon + text blocks: "Enter the job details", "Agent researches real candidate experiences", "Receive your personalized prep guide".
- A static sample prep guide accordion showing what a completed output looks like, so visitors understand the value before signing up.
- No Stimulus or Turbo behavior.

---

### `dashboard/show.html.erb`

Replaces the boilerplate placeholder. Shows:
- Greeting with the user's first name.
- A "New Prep Session" primary button (accent green).
- An inline Bootstrap info alert if the user has no `JobSeekerProfile` or an empty `background_summary`, prompting them to complete their profile.
- A list of the user's 5 most recent `PrepSession` records: company name, job title, status badge, created-at date, and a link to the session.

---

### `job_seeker_profiles/edit.html.erb`

A single-field form with a `textarea` for `background_summary`. Includes a character counter showing characters remaining toward the 2000-character maximum, managed by a Stimulus controller. Save button labeled "Save Background Summary". Standard form POST with redirect; no Turbo Frame.

---

### `prep_sessions/index.html.erb`

Table of all the user's prep sessions. Columns: company, job title, status badge (color-coded: green for complete, yellow for pending/researching, red for failed), created-at date, view link, delete button. Empty state card with "Start your first prep session" call to action.

---

### `prep_sessions/new.html.erb`

Form with three fields:
- Job title (text input, required)
- Company (text input, required)
- Job description (optional textarea, placeholder: "Paste the job posting for more tailored questions")

If the user has no `background_summary`, an inline Bootstrap warning alert above the form reads: "Add a background summary to your profile so the prep guide can tailor STAR outlines to your experience." with a link to edit their profile. The form still submits without a background summary; the missing field results in a less personalized guide.

Submit button labeled "Research and Build My Prep Guide". Standard form POST with redirect; no Turbo Frame on the form itself.

---

### `prep_sessions/show.html.erb`

Renders one of three states:

**In-progress state (`status: pending` or `researching`).**
A `<turbo-frame id="prep-guide-status">` that sets its `src` to `prep_sessions/:id/status` and refreshes every 3 seconds via a `data-turbo-action="replace"` polling Stimulus controller. Inside the frame: a spinner in the secondary purple accent color, the text "Researching [Company] interview experiences...", and the agent progress feed showing the most recent tool call (populated by Turbo Stream broadcasts from the job).

**Complete state (`status: complete`).**
The `prep-guide-status` frame is replaced with the full prep guide partial (`_prep_guide.html.erb`).

**Failed state (`status: failed`).**
The frame shows a Bootstrap danger alert with the error message from `PrepSession#error_message` and a "Try again" button that links to `prep_sessions/new` with the session's `job_title` and `company` pre-filled.

---

### `prep_sessions/_prep_guide.html.erb`

The main output partial. Structure:

- Page heading: "Prep Guide: [Job Title] at [Company]"
- An inline disclaimer callout (Bootstrap info card): "This prep guide is based on publicly available sources. Verify the listed sources yourself before treating any information as current or authoritative. Interview processes change frequently."
- A Bootstrap accordion with 5 panels, one per likely question. Panel header shows the question text. Open panel body shows the STAR outline with labeled Situation, Task, Action, and Result fields.
- A second accordion section labeled "Company-specific signals" with the 2 talking points to reference.
- A third section labeled "Smart questions to ask" rendered as a numbered `<ol>` of 3 items.
- A watch-out callout (custom `watch-out-callout` CSS class with purple left border): "Watch out: [watch_out text]".
- A "Sources the agent consulted" Bootstrap collapse section listing each URL from `PrepGuide#sources` as a clickable `<a>` link.
- A "Show raw response" Bootstrap collapse toggle revealing `PrepGuide#gemini_raw` in a `<pre>` block. Required per boilerplate convention.

---

### Stimulus Controllers (New)

- **`character-counter`**: Reads a `data-max-length` value, counts characters in the connected textarea, and updates a linked badge element with the remaining count. Turns red when under 100 characters remaining. Used on the `background_summary` textarea.
- **`polling`**: Manages the Turbo Frame polling cycle on the prep session show page. Starts on controller connect; reads the current status from a `data-status` attribute on the frame and stops polling when the value is `complete` or `failed`.

---

## 7. AI Templates and Gemini Integration

### Template: `interviewbump_prep_guide_v1`

**Description:** Research a specific company's interview process for a specific role using web search and page fetching, then synthesize a personalized prep guide tailored to the candidate's background.

---

**Full System Prompt:**

```
You are an expert interview research agent. Your job is to investigate how a specific company actually interviews for a specific role by searching publicly available sources, then synthesize that intelligence into a personalized prep guide for the candidate.

You have access to two tools:
- search_web(query): Searches the web and returns a list of result titles, URLs, and short snippets.
- fetch_url(url): Fetches the full text content of a URL, truncated to 2500 characters.

Your research strategy:
1. Search for candid candidate experiences on Reddit: search_web("[company] [job title] interview questions site:reddit.com")
2. Search for Glassdoor interview reports: search_web("[company] [job title] interview experience Glassdoor")
3. Search for company engineering culture: search_web("[company] engineering culture values interview process")
4. From your search results, select the single most useful URL and call fetch_url to read it in full. Prefer Reddit threads or Glassdoor reviews with visible candidate accounts over news articles or company PR pages.
5. After completing your searches and fetch, stop calling tools and write the final prep guide.

Rules:
- Run a minimum of 3 searches and a maximum of 5 total tool calls before synthesizing.
- Search specifically for this company and this role type, not for generic interview advice.
- If a search returns no useful results, try one alternative query before moving on.
- Do not fabricate specific interview questions or candidate experiences. Only synthesize what your sources actually contain. If sources contain no useful information about this company's interview process, say so clearly and note that the guide is based on general patterns for this role type at companies of similar size and stage.
- The STAR outlines must be tailored to the candidate's background summary. Do not write generic placeholders. Use the specific experience and skills described to make each outline concrete and plausible.

Output format: return a single JSON object with exactly these keys:

{
  "likely_questions": ["question 1", "question 2", "question 3", "question 4", "question 5"],
  "star_outlines": [
    {
      "question": "question text",
      "situation": "specific situation from the candidate's background",
      "task": "what was required",
      "action": "specific actions the candidate took",
      "result": "outcome and what was learned"
    }
  ],
  "questions_to_ask": ["question 1", "question 2", "question 3"],
  "watch_out": "One specific pattern in this company's interviews that catches candidates off guard.",
  "company_signals": [
    "A specific thing to reference that signals genuine research, with context for why it matters.",
    "A second specific thing to reference."
  ]
}

Return ONLY valid JSON. No explanatory text before or after the JSON object. Every array must have exactly the number of items specified.
```

---

**Full User Prompt Template:**

```
I am preparing for a {{job_title}} interview at {{company}}.

My background:
{{background_summary}}

{{job_description}}

Research how {{company}} actually interviews for {{job_title}} roles. Search for real candidate experiences on Reddit and Glassdoor. Fetch the most useful result you find. Then write a prep guide tailored specifically to my background above.
```

Note: `{{job_description}}` is rendered as "Job description:\n[content]" when the field is populated, and omitted entirely from the rendered prompt when blank. This conditional rendering is handled by the job before passing variables to `GeminiService`.

---

**Variables consumed:**

- `{{job_title}}` - from `PrepSession#job_title`
- `{{company}}` - from `PrepSession#company`
- `{{background_summary}}` - from `JobSeekerProfile#background_summary` for the session's user; falls back to "No background summary provided." if the profile is missing
- `{{job_description}}` - from `PrepSession#job_description`; omitted from prompt if blank

---

**Model:** `gemini-2.0-flash`

The agent loop runs 3 to 5 tool calls before synthesis. Flash's lower latency keeps total agent duration at approximately 15 to 30 seconds for a typical run, which is acceptable for a background job with a visible progress feed.

**Max Output Tokens:** 3000

Five STAR outlines with full Situation, Task, Action, and Result fields for each run long. 2000 tokens causes truncation on longer outlines. 3000 gives room for complete output.

**Temperature:** 0.4

Lower than the boilerplate default (0.7). The agent's research-then-synthesize structure requires structured and accurate output, not creative output. Lower temperature also reduces hallucination risk in STAR outlines, which must be grounded in the candidate's actual background rather than invented scenarios.

---

**Notes (author's notes):**

The most important prompt engineering decision is the instruction prohibiting fabrication of specific interview experiences. Early iterations hallucinated plausible-sounding Glassdoor reviews. The instruction plus low temperature substantially reduced this; verify in the admin test panel that the agent is citing sources it actually fetched before treating the output as reliable.

Watch for the agent skipping the fetch_url call when search snippets appear sufficient. The system prompt requires at least one fetch; reinforce this requirement if you observe the pattern.

Glassdoor frequently returns a login-wall page when fetched. The agent handles this naturally in most runs by falling back to Reddit results. No specific prompt instruction is needed for this case, but monitor the admin LLM request log if users report empty source lists.

If output is freeform text instead of JSON, add "Return ONLY valid JSON. No text before or after." to the end of the system prompt. The current final line already says this; repeat it if the problem persists.

Temperature changes matter here more than in most templates. 0.6 produces more narrative STAR outlines; 0.3 produces more bullet-like and predictable ones. Experiment in the test panel and settle on the value that produces outlines that feel both specific and natural.

---

**Where it is called:** `PrepGuideJob#perform`, via `GeminiService.generate_with_tools(template: "interviewbump_prep_guide_v1", variables: {job_title:, company:, background_summary:, job_description:}, tools: [search_web_tool, fetch_url_tool])`.

---

**Expected output format:** JSON object with exactly the schema defined in the system prompt. The response is parsed with `JSON.parse(result)` and each key's value is stored to the corresponding `PrepGuide` field.

**How the response is parsed and rendered:**

```ruby
parsed = JSON.parse(result)
PrepGuide.create!(
  prep_session: prep_session,
  likely_questions: parsed["likely_questions"].to_json,
  star_outlines: parsed["star_outlines"].to_json,
  questions_to_ask: parsed["questions_to_ask"].to_json,
  watch_out: parsed["watch_out"],
  company_signals: parsed["company_signals"].to_json,
  sources: collected_sources.to_json,
  agent_trace: agent_trace.to_json,
  gemini_raw: result
)
```

`collected_sources` is an array of URLs accumulated from every `fetch_url` tool call during the agent loop. `agent_trace` is an array of `{tool, input, result_preview, timestamp}` hashes, one per tool call. Both are accumulated by the job's tool dispatch loop before being stored.

The `_prep_guide.html.erb` partial calls `JSON.parse` on each JSON field before iterating.

**Raw response field:** `PrepGuide#gemini_raw`

---

### Agent Tool Definitions

**`search_web(query: string)`**

Implementation calls `https://google.serper.dev/search` via the Serper.dev API using `SERPER_API_KEY` from the environment. Returns an array of `{title, url, snippet}` objects from the top 5 organic results. The result is appended to `agent_trace` as a tool call record with `tool: "search_web"`, `input: query`, and `result_preview:` (the first two result titles and URLs).

**`fetch_url(url: string)`**

Makes an HTTP GET to the provided URL. Strips HTML tags from the response body using a simple regex, then truncates to 2500 characters before returning the content to Gemini. Adds the URL to the `collected_sources` array. Appends a trace record with `tool: "fetch_url"`, `input: url`, and `result_preview:` (first 200 characters of stripped content).

**Maximum loop count:** 5 rounds. If Gemini continues requesting tool calls after 5 rounds, the loop terminates and synthesis proceeds with whatever research has been accumulated up to that point.

**Intermediate state display:**

As each tool call completes, the job broadcasts a Turbo Stream `update` to a broadcast channel keyed on `"prep_session_#{prep_session.id}"`. The `<turbo-frame>` on the show page subscribes to this channel and updates the agent progress feed with the most recent tool call: tool name plus truncated query or URL. This gives the user visible forward progress without requiring a page refresh.

**Sources and agent_trace storage:** The job accumulates `collected_sources` (URLs from all `fetch_url` calls) and `agent_trace` (one record per tool call) in memory during the loop. Both are serialized to JSON and stored on `PrepGuide` after the synthesis step completes successfully.

---

## 8. AI Safety Considerations

### Content Sensitivity

Interview prep is career-consequential. A user who acts on a factually wrong prep guide risks performing poorly in an interview or walking in with false expectations about a company's process. This is not in the same category as health or legal advice, but the stakes are real enough to warrant explicit treatment.

The primary risk is hallucination: the agent synthesizing specific interview questions or candidate experiences that no source actually contained. The system prompt explicitly prohibits this, the low temperature (0.4) reduces it, and the "Sources the agent consulted" section on every prep guide is the primary user-facing mitigation - it shows the actual URLs so users can verify claims before treating the guide as authoritative. An agent that fabricated experiences and listed no sources it actually fetched would be caught immediately by a user who checks the links.

### App-Specific Disclaimer

The prep guide output page includes, in addition to the boilerplate footer disclaimer, an inline callout at the top of every guide: "This prep guide is based on publicly available sources. Verify the listed sources yourself before treating any information as current or authoritative. Interview processes change frequently."

### Tightened Settings

- Temperature is set to 0.4, lower than the boilerplate default of 0.7, to reduce hallucination in STAR outlines and improve JSON structure reliability.
- The 5-round agent loop cap prevents runaway API calls while allowing thorough research.
- `max_output_tokens` is 3000 rather than the boilerplate default of 2000. This is a deliberate relaxation: truncated STAR outlines are worse for the user than longer complete ones.

### What This Demo Deliberately Does Not Do

- **Source credibility scoring.** The agent does not rank sources by recency, upvote count, or reply volume. A production app would weight recent Glassdoor reviews over posts from 2018 and favor highly upvoted Reddit threads. The in-app disclaimer covers the recency limitation.
- **Interview date filtering.** The agent cannot determine whether a Glassdoor review reflects the company's current process or a process from three years ago. The disclaimer addresses this.
- **PII detection in background_summary.** The boilerplate gatekeeper catches prompt injection attempts but does not scrub PII from the user's background summary. The README warns users not to include genuinely sensitive personal information, though a career background summary is low-risk by nature.
- **Employer verification.** The app does not verify that the company the user enters is a real employer. Typos or fictional companies result in searches that return no useful results; the agent surfaces this clearly in the output rather than fabricating results.
- **Job description parsing.** The pasted job description is injected into the prompt as-is. A production app would parse and structure it. For a demo with a 2500-character Gemini context per fetch, the risk of a very long job description crowding out the background summary is real; the 2000-character cap on `background_summary` mitigates this partially.

---

## 9. RSpec Outline

### `spec/models/job_seeker_profile_spec.rb`

- Validates presence of `background_summary`
- Validates `background_summary` maximum length (2000 characters; exactly 2000 is valid; 2001 is not)
- Validates presence of `user_id`
- `belongs_to :user` association resolves correctly

### `spec/models/prep_session_spec.rb`

- Validates presence of `job_title`, `company`, and `user_id`
- Validates `status` inclusion in the allowed set; rejects arbitrary strings
- `belongs_to :user` association resolves correctly
- `has_one :prep_guide` association resolves correctly
- Destroying a `PrepSession` cascades to its `PrepGuide`

### `spec/models/prep_guide_spec.rb`

- Validates presence of `prep_session_id`
- `belongs_to :prep_session` association resolves correctly
- `sources` and `agent_trace` stored as valid JSON can be round-tripped through `JSON.parse`

### `spec/requests/prep_sessions_spec.rb`

- `GET /prep_sessions` redirects unauthenticated users to sign in
- `GET /prep_sessions` returns only the current user's sessions; another user's session is not present in the response
- `POST /prep_sessions` with valid params creates a `PrepSession` with `status: "pending"` and enqueues `PrepGuideJob`
- `POST /prep_sessions` with missing `job_title` re-renders the form with an error and does not enqueue the job
- `GET /prep_sessions/:id` for a completed session renders the prep guide partial content
- `GET /prep_sessions/:id` for a pending session renders the progress UI content (spinner present, prep guide partial absent)
- `GET /prep_sessions/:id` for another user's session returns 404
- `DELETE /prep_sessions/:id` destroys the session and redirects to the sessions index
- `DELETE /prep_sessions/:id` for another user's session returns 404

### `spec/requests/job_seeker_profiles_spec.rb`

- `GET /job_seeker_profile/edit` redirects unauthenticated users to sign in
- `PATCH /job_seeker_profile` with a valid `background_summary` upserts the profile and redirects to dashboard
- `PATCH /job_seeker_profile` with a `background_summary` over 2000 characters re-renders the form with a validation error

### `spec/jobs/prep_guide_job_spec.rb`

- When the Gemini stub returns a valid JSON response, creates a `PrepGuide` record with all fields populated and non-nil
- Updates `PrepSession#status` to `"complete"` on a successful run
- Updates `PrepSession#status` to `"failed"` when `GeminiService::GeminiError` is raised; `error_message` is populated
- An `LlmRequest` record exists after a successful run (verified through the stub returning one)
- `agent_trace` contains at least one tool call record after a successful run
- `sources` on the created `PrepGuide` is a non-empty JSON array after a successful run
- The agent loop terminates within 5 rounds when the stub always returns a tool call response (does not loop indefinitely)

---

## 10. Seed Data

### AiTemplate Seeds

`db/seeds.rb` creates the following record after the boilerplate's seeded admin user:

```ruby
AiTemplate.find_or_create_by!(name: "interviewbump_prep_guide_v1") do |t|
  t.description = "Research a company's interview process for a specific role and build a personalized prep guide."
  t.system_prompt = # full system prompt text from Section 7
  t.user_prompt_template = # full user prompt template text from Section 7
  t.model = "gemini-2.0-flash"
  t.max_output_tokens = 3000
  t.temperature = 0.4
  t.notes = "Keep temperature at 0.4 to reduce hallucination in STAR outlines. Verify in the test panel that the agent is fetching at least one URL before synthesizing. If output is freeform text instead of JSON, reinforce the JSON-only instruction at the end of the system prompt."
end
```

### Domain Seeds

The seed file creates a `JobSeekerProfile` and two `PrepSession` records for the demo user to populate the app with realistic content on first run.

**Profile seed:**

```ruby
profile = JobSeekerProfile.find_or_create_by!(user: demo_user) do |p|
  p.background_summary = "5 years of backend engineering experience in Python and Go. Strong in distributed systems, API design, and production debugging. Led a small engineering team at a Series B startup. Looking for senior IC roles at mid-size product companies."
end
```

**Completed session seed:**

A `PrepSession` for the demo user with `job_title: "Senior Software Engineer"`, `company: "Stripe"`, `status: "complete"`, and an associated `PrepGuide` with realistic sample content: 5 questions reflecting what public sources report about Stripe's engineering interview (systems design, distributed systems, incident response, cross-functional collaboration, and one behavioral leadership question), STAR outlines tailored to the background summary above, 3 smart questions about Stripe's infrastructure team structure, a `watch_out` noting that Stripe heavily weights written communication exercises that candidates frequently underestimate, and 2 `company_signals` referencing Stripe's API-first culture and their public engineering blog posts on reliability. `sources` is a JSON array with two realistic Glassdoor and Reddit URLs as placeholders.

**In-progress session seed:**

A `PrepSession` with `job_title: "Backend Engineer"`, `company: "Notion"`, `status: "pending"`, and no associated `PrepGuide`. This demonstrates the in-progress state on the show page when the demo app is first explored.

---

## 11. README Additions

### InterviewBump Demo

**Tagline:** Tell it the company and role. The agent researches real interview experiences and builds your prep guide.

InterviewBump Demo shows what interview prep looks like when you replace generic lists with real intelligence about how a specific company interviews for a specific role. Enter a job title, company name, and a short background summary. A Gemini agent searches Reddit and Glassdoor for real candidate experiences, fetches the most useful result it finds, and synthesizes a prep guide with the 5 most likely questions for this company and role, STAR outlines tailored to your background, smart questions to ask the interviewer, and one company-specific watch-out.

This is a demo of one feature from InterviewBump, a multi-tenant SaaS tool I am building for individual contributors and small teams preparing for technical and behavioral interviews. The production version adds team workspaces, manager-assigned prep workflows, and prep history across a job search. [View the full product at interviewbump.com] (placeholder URL). The demo is open source under the MIT license; clone it, run it, tune the prompt.

---

**Screenshot placeholder:** `[Screenshot: The completed prep guide for "Senior Software Engineer at Stripe" - showing the 5-question accordion with the first panel expanded to reveal the STAR outline, the watch-out callout in purple, and the "Sources the agent consulted" collapse section at the bottom.]`

---

### Why I Built This

Generic interview prep is a solved problem. There are dozens of apps and countless YouTube videos covering STAR format and "what's your greatest weakness." The hard part is not knowing the framework; the hard part is knowing that this specific company weights systems design differently than its peers, or that their behavioral round focuses on a theme candidates don't expect, or that the two questions everyone who got an offer prepared deeply for are not the ones on the generic lists. That intelligence exists publicly - candidates post their real experiences on Reddit and Glassdoor after every interview cycle - but finding, reading, and synthesizing it the night before an interview takes time most people don't have.

I built InterviewBump to answer one question: what if your prep guide started from real intelligence about this specific company and role, not a template that has been copied and pasted since 2015? The agent does the research; you do the practicing.

---

### Additional Setup

In addition to `bin/setup` and setting `GEMINI_API_KEY`, this demo requires a Serper.dev API key for the web search tool:

1. Sign up at [serper.dev](https://serper.dev) (free tier, 2500 queries per month)
2. Copy your API key from the Serper dashboard
3. Add `SERPER_API_KEY=your_key_here` to your `.env` file

Without `SERPER_API_KEY`, the agent will fail on the first `search_web` tool call and the prep guide generation will error. The failure surfaces as a `GeminiService::GeminiError` with an error message referencing the missing key and displays the retry UI on the session show page.

---

### Prompt Customization

The agent's research strategy and output format are fully editable without restarting the server. Sign in as `demo@example.com` / `password123`, navigate to `/admin/ai_templates`, and open `interviewbump_prep_guide_v1`. The test panel lets you enter sample variable values (job_title, company, background_summary) and run the agent live to see the full output and tool call trace.

Common experiments to try:
- Add a fourth search query targeting the company's engineering blog
- Change the number of STAR outlines from 5 to 3 for a more focused output
- Adjust temperature between 0.3 (more structured) and 0.6 (more narrative) to see the effect on STAR outline quality

---

## 12. Bootstrap Dark Mode and Accent Color Notes

### UX Pattern

Form-then-agent-progress with accordion output. The primary interaction is two steps: fill a short form (two required fields), then wait with a progress feed while the agent runs. The output is an accordion. This pattern requires no complex Stimulus beyond polling and character counting.

### Accent Color Application

- Primary buttons ("Research and Build My Prep Guide", "New Prep Session", "Save Background Summary"): accent green via Bootstrap `.btn-primary` override
- Active navbar link (e.g., "My Sessions" when on the sessions index): `color: var(--accent)` via `.nav-link.active` override
- Status badge for `complete` sessions: Bootstrap `.badge` with accent green background
- Accordion panel headers in the open state: light green background tint via the prep-guide-accordion rule below
- "Sources" section links: `color: var(--accent)` for consistency with primary interactive elements

Secondary accent `#7c3aed` (purple) is used for:
- The agent-in-progress spinner (visually distinct from the green primary action color, signals a different phase)
- The "Watch out" callout border (distinct from Bootstrap's default warning yellow, which does not read well in dark mode against dark backgrounds)

### Custom CSS

Beyond `_accent.scss`, this app adds the following rules to `application.css`:

```css
.prep-guide-accordion .accordion-button:not(.collapsed) {
  background-color: rgba(22, 163, 74, 0.1);
  color: var(--accent);
  box-shadow: none;
}

.agent-progress-feed {
  border-left: 3px solid #7c3aed;
  padding-left: 1rem;
  font-size: 0.875rem;
  color: var(--bs-secondary-color);
}

.watch-out-callout {
  border-left: 4px solid #7c3aed;
  background-color: rgba(124, 58, 237, 0.08);
  padding: 1rem;
  border-radius: 0.375rem;
  margin-top: 1.5rem;
}
```

All other styling uses standard Bootstrap utilities. No additional CSS files beyond these additions and `_accent.scss`.

---

*v1.0 - InterviewBump Demo spec. Built on Open Demo Starter v2.0. Open source under MIT license.*
