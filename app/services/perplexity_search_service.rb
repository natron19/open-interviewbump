require "faraday"

class PerplexitySearchService
  ENDPOINT = "https://api.perplexity.ai/chat/completions"
  MODEL    = "sonar"

  def self.search(query)
    new.search(query)
  end

  def search(query)
    api_key = ENV["PERPLEXITY_API_KEY"]
    raise GeminiService::GeminiError, "PERPLEXITY_API_KEY missing — configure it to enable web search" if api_key.blank?

    http = Faraday.new do |conn|
      conn.request  :json
      conn.response :json
      conn.options.timeout      = 30
      conn.options.open_timeout = 10
      conn.adapter  Faraday.default_adapter
    end

    response = http.post(ENDPOINT) do |req|
      req.headers["Authorization"] = "Bearer #{api_key}"
      req.body = {
        model:    MODEL,
        messages: [{ role: "user", content: query }]
      }
    end

    unless response.success?
      raise GeminiService::GeminiError,
            "Perplexity search failed (#{response.status}): #{response.body.to_s.truncate(200)}"
    end

    body    = response.body
    answer  = body.dig("choices", 0, "message", "content").to_s
    sources = Array(body["citations"])

    { answer: answer, sources: sources }
  rescue GeminiService::GeminiError
    raise
  rescue => e
    raise GeminiService::GeminiError, "Web search error: #{e.message.truncate(200)}"
  end
end
