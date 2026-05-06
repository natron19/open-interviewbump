require "faraday"
require "json"

class GeminiService
  class GeminiError         < StandardError; end
  class GatekeeperError     < GeminiError;   end
  class BudgetExceededError < GeminiError;   end
  class TimeoutError        < GeminiError;   end

  TIMEOUT_SECONDS       = ENV.fetch("AI_GLOBAL_TIMEOUT_SECONDS", "15").to_i
  AGENT_TIMEOUT_SECONDS = ENV.fetch("AI_AGENT_TIMEOUT_SECONDS",  "45").to_i
  BASE_URL              = "https://generativelanguage.googleapis.com/v1beta"

  def self.generate(template:, variables: {}, user: Current.user)
    new(template:, variables:, user:).generate
  end

  def self.generate_with_tools(template:, variables: {}, tools: {}, user: Current.user, on_tool_call: nil)
    new(template:, variables:, user:).generate_with_tools(tools:, on_tool_call:)
  end

  def initialize(template:, variables: {}, user:)
    @template_name = template
    @variables     = variables
    @user          = user
  end

  def generate
    ai_template     = AiTemplate.find_by!(name: @template_name)
    rendered_prompt = ai_template.interpolate(@variables)

    begin
      AiGatekeeper.check!(rendered_prompt, @user)
    rescue GatekeeperError => e
      LlmRequest.create!(
        user: @user, ai_template: ai_template, template_name: ai_template.name,
        status: "gatekeeper_blocked", error_message: e.message
      ) if @user
      raise
    end

    if @user
      begin
        AiBudgetChecker.check!(@user)
      rescue BudgetExceededError => e
        LlmRequest.create!(
          user: @user, ai_template: ai_template, template_name: ai_template.name,
          status: "budget_exceeded", error_message: e.message
        )
        raise
      end
    end

    log = LlmRequest.create!(
      user:          @user,
      ai_template:   ai_template,
      template_name: ai_template.name,
      status:        "pending"
    )

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      response_text, prompt_tokens, response_tokens = call_gemini(ai_template, rendered_prompt)
      duration_ms = elapsed_ms(start_time)

      log.update!(
        status:               "success",
        prompt_token_count:   prompt_tokens,
        response_token_count: response_tokens,
        duration_ms:          duration_ms,
        cost_estimate_cents:  estimate_cost(prompt_tokens, response_tokens, ai_template.model)
      )

      response_text

    rescue Timeout::Error
      log.update!(
        status:        "timeout",
        duration_ms:   elapsed_ms(start_time),
        error_message: "Gemini call timed out after #{TIMEOUT_SECONDS}s"
      )
      raise TimeoutError, "The AI request timed out. Please try again."

    rescue GeminiError
      raise

    rescue => e
      api_body = e.respond_to?(:response) && e.response ? e.response[:body].to_s : ""
      log.update!(
        status:        "error",
        duration_ms:   elapsed_ms(start_time),
        error_message: (api_body.presence || e.message).truncate(500)
      )
      raise GeminiError, "An error occurred while generating a response."
    end
  end

  def generate_with_tools(tools: {}, on_tool_call: nil)
    ai_template     = AiTemplate.find_by!(name: @template_name)
    rendered_prompt = ai_template.interpolate(@variables)

    begin
      AiGatekeeper.check!(rendered_prompt, @user)
    rescue GatekeeperError => e
      LlmRequest.create!(
        user: @user, ai_template: ai_template, template_name: ai_template.name,
        status: "gatekeeper_blocked", error_message: e.message
      ) if @user
      raise
    end

    if @user
      begin
        AiBudgetChecker.check!(@user)
      rescue BudgetExceededError => e
        LlmRequest.create!(
          user: @user, ai_template: ai_template, template_name: ai_template.name,
          status: "budget_exceeded", error_message: e.message
        )
        raise
      end
    end

    log = LlmRequest.create!(
      user:          @user,
      ai_template:   ai_template,
      template_name: ai_template.name,
      status:        "pending"
    )

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      result = run_agent_loop(ai_template, rendered_prompt, tools, on_tool_call)
      duration_ms = elapsed_ms(start_time)

      log.update!(
        status:               "success",
        prompt_token_count:   result[:prompt_tokens],
        response_token_count: result[:response_tokens],
        duration_ms:          duration_ms,
        cost_estimate_cents:  estimate_cost(result[:prompt_tokens], result[:response_tokens], ai_template.model)
      )

      { text: result[:text], sources: [], agent_trace: [] }

    rescue Timeout::Error
      log.update!(status: "timeout", duration_ms: elapsed_ms(start_time),
                  error_message: "Gemini agent call timed out after #{AGENT_TIMEOUT_SECONDS}s")
      raise TimeoutError, "The AI request timed out. Please try again."

    rescue GeminiError
      raise

    rescue => e
      api_body = e.respond_to?(:response) && e.response ? e.response[:body].to_s : ""
      log.update!(status: "error", duration_ms: elapsed_ms(start_time),
                  error_message: (api_body.presence || e.message).truncate(500))
      raise GeminiError, "An error occurred while generating a response."
    end
  end

  private

  def run_agent_loop(ai_template, rendered_prompt, tools, on_tool_call)
    full_prompt = [ai_template.system_prompt.presence, rendered_prompt].compact.join("\n\n")

    tool_declarations = tools.values.map do |t|
      { name: t[:name], description: t[:description], parameters: t[:parameters] }
    end

    contents = [{ role: "user", parts: [{ text: full_prompt }] }]

    total_prompt_tokens   = 0
    total_response_tokens = 0
    http = build_http_client

    8.times do
      response = Timeout.timeout(AGENT_TIMEOUT_SECONDS) do
        http.post("#{BASE_URL}/models/#{ai_template.model}:generateContent") do |req|
          req.params["key"] = ENV.fetch("GEMINI_API_KEY")
          req.body = {
            contents:         contents,
            tools:            [{ functionDeclarations: tool_declarations }],
            generationConfig: {
              maxOutputTokens: ai_template.max_output_tokens,
              temperature:     ai_template.temperature.to_f
            }
          }
        end
      end

      raise StandardError, response.body.to_json unless response.success?

      body = response.body
      total_prompt_tokens   += body.dig("usageMetadata", "promptTokenCount").to_i
      total_response_tokens += body.dig("usageMetadata", "candidatesTokenCount").to_i

      parts = body.dig("candidates", 0, "content", "parts") || []

      # Record model turn in contents for next round
      contents << { role: "model", parts: parts }

      function_call_part = parts.find { |p| p["functionCall"] }

      if function_call_part
        fc   = function_call_part["functionCall"]
        name = fc["name"]
        args = fc["args"] || {}
        tool = tools[name]

        raise GeminiError, "Unknown tool: #{name}" unless tool

        on_tool_call&.call(name, args)
        result = tool[:callable].call(args)

        contents << {
          role:  "function",
          parts: [{
            functionResponse: {
              name:     name,
              response: result
            }
          }]
        }
      else
        text = parts.map { |p| p["text"].to_s }.join
        return { text: text, prompt_tokens: total_prompt_tokens, response_tokens: total_response_tokens }
      end
    end

    raise GeminiError, "Agent loop exceeded maximum rounds without producing a text response."
  end

  def build_http_client
    Faraday.new do |conn|
      conn.request  :json
      conn.response :json
      conn.adapter  Faraday.default_adapter
    end
  end

  def call_gemini(ai_template, rendered_prompt)
    full_prompt = [ai_template.system_prompt.presence, rendered_prompt].compact.join("\n\n")
    http = build_http_client

    response = Timeout.timeout(TIMEOUT_SECONDS) do
      http.post("#{BASE_URL}/models/#{ai_template.model}:generateContent") do |req|
        req.params["key"] = ENV.fetch("GEMINI_API_KEY")
        req.body = {
          contents: [{ parts: [{ text: full_prompt }] }],
          generationConfig: {
            maxOutputTokens: ai_template.max_output_tokens,
            temperature:     ai_template.temperature.to_f
          }
        }
      end
    end

    unless response.success?
      raise StandardError, response.body.to_json
    end

    body    = response.body
    text    = (body.dig("candidates", 0, "content", "parts") || [])
                .map { |p| p["text"].to_s }
                .join

    prompt_tokens   = body.dig("usageMetadata", "promptTokenCount")     || estimate_tokens(full_prompt)
    response_tokens = body.dig("usageMetadata", "candidatesTokenCount") || estimate_tokens(text)

    [text, prompt_tokens, response_tokens]
  end

  def estimate_tokens(text)
    (text.to_s.length / 4.0).ceil
  end

  def estimate_cost(prompt_tokens, response_tokens, model)
    input_rate  = 7.5
    output_rate = 30.0
    ((prompt_tokens * input_rate) + (response_tokens * output_rate)) / 1_000_000.0
  end

  def elapsed_ms(start)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
  end
end
