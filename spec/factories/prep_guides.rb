FactoryBot.define do
  factory :prep_guide do
    prep_session
    likely_questions { '["Question 1","Question 2","Question 3","Question 4","Question 5"]' }
    star_outlines    { '[{"question":"Question 1","situation":"Situation","task":"Task","action":"Action","result":"Result"}]' }
    questions_to_ask { '["Smart question 1","Smart question 2","Smart question 3"]' }
    watch_out        { "Candidates often underestimate the written exercise." }
    company_signals  { '["Signal one: API-first culture","Signal two: reliability engineering"]' }
    sources          { '["https://reddit.com/r/cscareerquestions/example"]' }
    agent_trace      { '[{"tool":"search_web","input":"Acme Corp Software Engineer interview","result_preview":"Result 1 - https://reddit.com","timestamp":"2026-01-01T00:00:00Z"}]' }
    gemini_raw       { '{"likely_questions":["Question 1","Question 2","Question 3","Question 4","Question 5"]}' }
  end
end
