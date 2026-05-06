require "faraday"
require "json"

class SerperSearchService
  ENDPOINT = "https://google.serper.dev/search"

  def self.search(query, num: 5)
    new.search(query, num:)
  end

  def search(query, num: 5)
    api_key = ENV["SERPER_API_KEY"]
    raise GeminiService::GeminiError, "SERPER_API_KEY missing — configure it to enable web search" if api_key.blank?

    http = Faraday.new do |conn|
      conn.request  :json
      conn.response :json
      conn.adapter  Faraday.default_adapter
    end

    response = http.post(ENDPOINT) do |req|
      req.headers["X-API-KEY"]     = api_key
      req.headers["Content-Type"]  = "application/json"
      req.body = { q: query, num: num }
    end

    unless response.success?
      raise GeminiService::GeminiError, "Serper search failed (#{response.status}): #{response.body.to_s.truncate(200)}"
    end

    (response.body["organic"] || []).map do |r|
      { title: r["title"].to_s, url: r["link"].to_s, snippet: r["snippet"].to_s }
    end
  rescue GeminiService::GeminiError
    raise
  rescue => e
    raise GeminiService::GeminiError, "Web search error: #{e.message.truncate(200)}"
  end
end
