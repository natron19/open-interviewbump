require "net/http"
require "uri"

class PrepGuideJob < ApplicationJob
  queue_as :default

  def perform(prep_session_id)
    prep_session = PrepSession.find(prep_session_id)
    user         = prep_session.user

    prep_session.update!(status: "researching")
    log_progress(prep_session, "Researching #{prep_session.company} interview experiences...")

    background_summary = user.job_seeker_profile&.background_summary.presence ||
                         "No background summary provided."
    job_desc_block     = prep_session.job_description.present? ?
                         "Job description:\n#{prep_session.job_description}" : ""

    collected_sources = []
    agent_trace       = []

    search_web_tool = {
      name:        "search_web",
      description: "Search the web and return top results.",
      parameters:  {
        type:       "OBJECT",
        properties: { query: { type: "STRING", description: "The search query" } },
        required:   ["query"]
      },
      callable: ->(args) {
        result = PerplexitySearchService.search(args["query"])
        result[:sources].each { |url| collected_sources << url }
        preview = result[:answer].first(200)
        agent_trace << { tool: "search_web", input: args["query"], result_preview: preview,
                         timestamp: Time.current.iso8601 }
        log_progress(prep_session, "search_web: #{args["query"].truncate(80)}")
        { answer: result[:answer], sources: result[:sources] }
      }
    }

    fetch_url_tool = {
      name:        "fetch_url",
      description: "Fetch the full text content of a URL.",
      parameters:  {
        type:       "OBJECT",
        properties: { url: { type: "STRING", description: "The URL to fetch" } },
        required:   ["url"]
      },
      callable: ->(args) {
        content = fetch_url_content(args["url"])
        collected_sources << args["url"]
        preview = content.first(200)
        agent_trace << { tool: "fetch_url", input: args["url"], result_preview: preview,
                         timestamp: Time.current.iso8601 }
        log_progress(prep_session, "fetch_url: #{args["url"].truncate(80)}")
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
      user:  user
    )

    raw_text = result[:text]
    clean    = raw_text.gsub(/\A```json\s*/m, "").gsub(/\s*```\z/m, "").strip
    parsed   = JSON.parse(clean)

    PrepGuide.create!(
      prep_session:     prep_session,
      likely_questions: parsed["likely_questions"].to_json,
      star_outlines:    parsed["star_outlines"].to_json,
      questions_to_ask: parsed["questions_to_ask"].to_json,
      watch_out:        parsed["watch_out"],
      company_signals:  parsed["company_signals"].to_json,
      sources:          collected_sources.to_json,
      agent_trace:      agent_trace.to_json,
      gemini_raw:       raw_text
    )

    prep_session.update!(status: "complete")

  rescue GeminiService::GeminiError => e
    prep_session&.update!(status: "failed", error_message: e.message)

  rescue JSON::ParserError => e
    prep_session&.update!(
      status:        "failed",
      error_message: "Failed to parse AI response: #{e.message.truncate(200)}"
    )

  rescue => e
    prep_session&.update!(
      status:        "failed",
      error_message: "Unexpected error: #{e.message.truncate(200)}"
    )

  ensure
    Current.user = nil
  end

  private

  def fetch_url_content(url)
    uri      = URI.parse(url)
    http     = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl     = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 10
    request  = Net::HTTP::Get.new(uri.request_uri,
                                  "User-Agent" => "Mozilla/5.0 (compatible; InterviewBump/1.0)")
    response = http.request(request)
    body     = response.body.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    stripped = body.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
    stripped.first(2500)
  rescue => e
    "[Could not fetch URL: #{e.message}]"
  end

  def log_progress(prep_session, message)
    Rails.logger.info("PrepGuideJob [#{prep_session.id}]: #{message}")
  end
end
