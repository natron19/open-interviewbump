# Admin user — credentials for local demo use only
demo_user = User.find_or_create_by!(email: "demo@example.com") do |u|
  u.name                  = "Demo User"
  u.password              = "password123"
  u.password_confirmation = "password123"
  u.admin                 = true
end

puts "Demo user: demo@example.com / password123"

# Health ping template — used by /up/llm
AiTemplate.find_or_create_by!(name: "health_ping") do |t|
  t.description          = "Minimal prompt used by the /up/llm health check endpoint."
  t.system_prompt        = "You are a health check endpoint. Respond with exactly: ok"
  t.user_prompt_template = "ping"
  t.model                = "gemini-2.5-flash"
  t.max_output_tokens    = 10
  t.temperature          = 0.0
  t.notes                = "Do not modify. Used by HealthController#llm."
end

puts "Seeded: health_ping AI template"

# InterviewBump prep guide template — always update so prompt changes take effect
interviewbump_template = AiTemplate.find_or_initialize_by(name: "interviewbump_prep_guide_v1")
interviewbump_template.assign_attributes(
  description: "Research a company's interview process for a specific role and build a personalized prep guide.",
  system_prompt: <<~PROMPT.strip,
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
    - star_outlines MUST contain exactly 5 items — one for each of the 5 likely_questions, in the same order.
    - Keep each STAR field (situation, task, action, result) to 1–2 sentences maximum. Be specific but concise. Total JSON response must fit within 8000 tokens.

    Output format: return a single JSON object with exactly these keys:

    {
      "likely_questions": ["question 1", "question 2", "question 3", "question 4", "question 5"],
      "star_outlines": [
        {
          "question": "exact text of question 1",
          "situation": "specific situation from the candidate's background",
          "task": "what was required",
          "action": "specific actions the candidate took",
          "result": "outcome and what was learned"
        },
        {
          "question": "exact text of question 2",
          "situation": "...",
          "task": "...",
          "action": "...",
          "result": "..."
        },
        {
          "question": "exact text of question 3",
          "situation": "...",
          "task": "...",
          "action": "...",
          "result": "..."
        },
        {
          "question": "exact text of question 4",
          "situation": "...",
          "task": "...",
          "action": "...",
          "result": "..."
        },
        {
          "question": "exact text of question 5",
          "situation": "...",
          "task": "...",
          "action": "...",
          "result": "..."
        }
      ],
      "questions_to_ask": ["question 1", "question 2", "question 3"],
      "watch_out": "One specific pattern in this company's interviews that catches candidates off guard.",
      "company_signals": [
        "A specific thing to reference that signals genuine research, with context for why it matters.",
        "A second specific thing to reference."
      ]
    }

    Return ONLY valid JSON. No explanatory text before or after the JSON object. star_outlines must have exactly 5 items. Every other array must have exactly the number of items shown above. Keep every string value under 150 words.
  PROMPT
  user_prompt_template: <<~PROMPT.strip,
    I am preparing for a {{job_title}} interview at {{company}}.

    My background:
    {{background_summary}}

    {{job_description}}

    Research how {{company}} actually interviews for {{job_title}} roles. Search for real candidate experiences on Reddit and Glassdoor. Fetch the most useful result you find. Then write a prep guide tailored specifically to my background above.
  PROMPT
  model:             "gemini-2.5-flash",
  max_output_tokens: 8000,
  temperature:       0.4,
  notes:             "Keep temperature at 0.4 to reduce hallucination in STAR outlines. star_outlines must have exactly 5 items. max_output_tokens at 8000 to ensure all 5 STAR outlines fit. Each STAR field capped at 1-2 sentences to keep total tokens manageable."
)
interviewbump_template.save!

puts "Seeded: interviewbump_prep_guide_v1 AI template"

# --- Domain seeds for demo user ---

# JobSeekerProfile
profile = JobSeekerProfile.find_or_create_by!(user: demo_user) do |p|
  p.background_summary = "5 years of backend engineering experience in Python and Go. Strong in distributed systems, API design, and production debugging. Led a small engineering team at a Series B startup. Looking for senior IC roles at mid-size product companies."
end

puts "Seeded: JobSeekerProfile for demo@example.com"

# Completed PrepSession — Stripe
stripe_session = PrepSession.find_or_create_by!(user: demo_user, company: "Stripe", job_title: "Senior Software Engineer") do |s|
  s.status = "complete"
end

unless stripe_session.prep_guide
  likely_questions = [
    "Tell me about a time you debugged a critical production incident under time pressure.",
    "How have you designed a system to handle high-throughput API requests reliably?",
    "Describe a time you influenced a technical decision beyond your immediate team.",
    "Tell me about the most complex distributed systems problem you have solved.",
    "How do you approach writing technical documentation or design docs?"
  ]

  star_outlines = [
    {
      question:  "Tell me about a time you debugged a critical production incident under time pressure.",
      situation: "Our payment API returned 500 errors to ~15% of requests during peak traffic on a Friday afternoon. My team owned the API layer between the checkout SDK and the bank processor.",
      task:      "Identify and resolve the root cause within 30 minutes without a blind full rollback that would lose in-flight transactions.",
      action:    "Pulled distributed traces, narrowed the error to a single downstream dependency timeout. Found a misconfigured threshold that only surfaced under peak concurrent load. Deployed a targeted config fix rather than a full rollback.",
      result:    "Error rate dropped to zero in 22 minutes. Wrote a postmortem that added timeout validation to CI, preventing a class of future incidents."
    },
    {
      question:  "How have you designed a system to handle high-throughput API requests reliably?",
      situation: "At my Series B startup processing 40k events/minute, the ingestion pipeline dropped events during traffic spikes because it was synchronous end-to-end.",
      task:      "Re-architect ingestion to decouple write acceptance from processing without a full rewrite or downtime.",
      action:    "Introduced a durable queue in front of processing workers. Made consumers idempotent. Added back-pressure so producers slowed gracefully. Rolled out behind a feature flag to validate throughput first.",
      result:    "Zero event loss under 3× peak load. P99 ingest latency fell from 800ms to 40ms."
    },
    {
      question:  "Describe a time you influenced a technical decision beyond your immediate team.",
      situation: "Three teams were independently building versions of the same rate-limiting logic, creating inconsistency and duplicated maintenance.",
      task:      "Propose a shared approach and drive adoption without formal authority.",
      action:    "Wrote a design doc comparing the three approaches with tradeoffs and a proposed interface. Async-reviewed it with each team's tech lead before any all-hands discussion.",
      result:    "All three teams adopted the shared library within one sprint, saving ~3 weeks of duplicated work that quarter."
    },
    {
      question:  "Tell me about the most complex distributed systems problem you have solved.",
      situation: "Our Go microservices cluster had intermittent consistency failures where read-after-write returned stale data under specific replication lag conditions.",
      task:      "Identify why the issue only appeared in production and design a fix that didn't require a full rewrite of the data layer.",
      action:    "Added structured logging to capture replication lag at each read. Confirmed the issue correlated with a specific replica set's lag spike pattern. Implemented read-your-writes consistency for the affected paths by routing those reads to the primary until a lag threshold was met.",
      result:    "Eliminated the stale read class of bugs. Lag-aware routing added <2ms to affected reads under normal conditions."
    },
    {
      question:  "How do you approach writing technical documentation or design docs?",
      situation: "At my startup, design docs were ad-hoc and often written after the fact, making onboarding and post-incident review painful.",
      task:      "Improve the team's design doc culture without adding bureaucracy that slowed down execution.",
      action:    "Introduced a lightweight one-page format: problem, options, decision, tradeoffs. Wrote the first three docs for systems I owned, then used those as templates in review feedback.",
      result:    "Team adopted the format voluntarily within two months. Onboarding new engineers went from 3 weeks to get up to speed on key systems to under 1 week."
    }
  ]

  PrepGuide.create!(
    prep_session:     stripe_session,
    likely_questions: likely_questions.to_json,
    star_outlines:    star_outlines.to_json,
    questions_to_ask: [
      "How does the infrastructure team structure ownership between platform engineering and product engineering — and how does that affect what a senior IC focuses on day to day?",
      "What does the on-call rotation look like for this team, and how has the team invested in reducing alert noise over the past year?",
      "You mentioned Stripe's API-first culture — how does that philosophy show up in internal tooling decisions, not just external-facing products?"
    ].to_json,
    watch_out:       "Stripe's written communication round surprises almost every candidate who hasn't been warned. You will be asked to write a short technical design doc or postmortem during the process. Candidates who treat it as a formality consistently report it was weighted more heavily than expected — treat it as seriously as any coding round.",
    company_signals: [
      "Reference Stripe's API-first culture specifically: their public engineering blog posts on how they think about API versioning and backwards compatibility signal genuine familiarity beyond 'they build payments'.",
      "Stripe's engineering blog posts on reliability engineering — particularly their documented approach to incident postmortems and blameless culture — are frequently cited by interviewers as part of how the team evaluates cultural fit."
    ].to_json,
    sources:         ["https://www.reddit.com/r/cscareerquestions/comments/stripe_interview_2024/",
                      "https://www.glassdoor.com/Interview/Stripe-Senior-Software-Engineer-Interview-Questions"].to_json,
    agent_trace:     [
      { tool: "search_web", input: "Stripe Senior Software Engineer interview questions site:reddit.com",
        result_preview: "r/cscareerquestions: Stripe SWE interview — what to expect | Stripe engineering interview 2024",
        timestamp: 2.minutes.ago.iso8601 },
      { tool: "search_web", input: "Stripe Senior Software Engineer interview experience Glassdoor",
        result_preview: "Glassdoor: Stripe SWE Interview — 4 rounds | Stripe interview process 2024",
        timestamp: 90.seconds.ago.iso8601 },
      { tool: "fetch_url", input: "https://www.reddit.com/r/cscareerquestions/comments/stripe_interview_2024/",
        result_preview: "Went through Stripe SWE loop last month. 4 rounds: 1 coding, 1 systems design, 1 written doc exercise, 1 behavioral...",
        timestamp: 60.seconds.ago.iso8601 }
    ].to_json,
    gemini_raw:      "{\"likely_questions\": [\"...\"], \"star_outlines\": [\"...\"]}"
  )

  puts "Seeded: PrepGuide for Stripe session"
end

# Pending PrepSession — Notion
PrepSession.find_or_create_by!(user: demo_user, company: "Notion", job_title: "Backend Engineer") do |s|
  s.status = "pending"
end

puts "Seeded: pending PrepSession for Notion"
