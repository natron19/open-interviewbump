require "faraday"
require "json"

class GeminiService
  class GeminiError         < StandardError; end
  class GatekeeperError     < GeminiError;   end
  class BudgetExceededError < GeminiError;   end
  class TimeoutError        < GeminiError;   end
  class OutputGuardError    < GeminiError;   end
  class CrisisError         < GatekeeperError; end

  TIMEOUT_SECONDS       = ENV.fetch("AI_GLOBAL_TIMEOUT_SECONDS", "15").to_i
  AGENT_TIMEOUT_SECONDS = ENV.fetch("AI_AGENT_TIMEOUT_SECONDS",  "45").to_i
  BASE_URL              = "https://generativelanguage.googleapis.com/v1beta"

  # gemini-2.5 models think before they answer, and thinking tokens count against maxOutputTokens.
  # Uncapped, thinking used up whole budgets (the JSON came back cut off) and made calls slow.
  # The budget caps thinking and is added on top of the template's limit, so max_output_tokens
  # stays the room for the answer itself. -1 lets Gemini decide (dynamic thinking).
  THINKING_BUDGET       = ENV.fetch("AI_THINKING_BUDGET", "1024").to_i

  # trusted: true skips the user-input gatekeeper. Only for internal callers whose
  # prompt is not user input (the eval harness LLM judge). Still logged and output-guarded.
  def self.generate(template:, variables: {}, user: Current.user, trusted: false)
    new(template:, variables:, user:, trusted:).generate
  end

  def self.generate_with_tools(template:, variables: {}, tools: {}, user: Current.user, on_tool_call: nil)
    new(template:, variables:, user:).generate_with_tools(tools:, on_tool_call:)
  end

  def initialize(template:, variables: {}, user:, trusted: false)
    @template_name = template
    @variables     = variables
    @user          = user
    @trusted       = trusted
  end

  def generate
    ai_template     = AiTemplate.find_by!(name: @template_name)
    rendered_prompt = ai_template.interpolate(@variables)

    begin
      AiGatekeeper.check!(rendered_prompt, @user) unless @trusted
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

      check_output!(log, ai_template, response_text, rendered_prompt)
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

      check_output!(log, ai_template, result[:text], rendered_prompt)
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

  def check_output!(log, ai_template, response_text, rendered_prompt)
    AiOutputGuard.check!(response_text, template: ai_template, input: rendered_prompt)
  rescue OutputGuardError => e
    log.update!(status: "output_blocked", error_message: e.message)
    raise
  end

  # Search results and fetched pages are third-party text: neutralize injection
  # in every string of the tool's response hash before the model sees it.
  def scan_tool_result(value)
    case value
    when String then AiGatekeeper.scan_untrusted(value)
    when Array  then value.map { |v| scan_tool_result(v) }
    when Hash   then value.transform_values { |v| scan_tool_result(v) }
    else value
    end
  end

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
          req.headers["x-goog-api-key"] = ENV.fetch("GEMINI_API_KEY")
          req.body = {
            contents:         contents,
            tools:            [{ functionDeclarations: tool_declarations }],
            generationConfig: self.class.generation_config(ai_template, json: false)
          }
        end
      end

      raise StandardError, response.body.to_json unless response.success?

      body = response.body
      total_prompt_tokens   += body.dig("usageMetadata", "promptTokenCount").to_i
      total_response_tokens += billed_output_tokens(body).to_i

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
        result = scan_tool_result(tool[:callable].call(args))

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
        text = AiOutputGuard.repair_json_text(parts.map { |p| p["text"].to_s }.join, ai_template.name)
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
        req.headers["x-goog-api-key"] = ENV.fetch("GEMINI_API_KEY")
        req.body = {
          contents: [{ parts: [{ text: full_prompt }] }],
          generationConfig: self.class.generation_config(ai_template)
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
    text    = AiOutputGuard.repair_json_text(text, ai_template.name)

    prompt_tokens   = body.dig("usageMetadata", "promptTokenCount")     || estimate_tokens(full_prompt)
    response_tokens = billed_output_tokens(body) || estimate_tokens(text)

    [text, prompt_tokens, response_tokens]
  end

  # json: false for requests that declare tools, which Gemini won't combine with a JSON response type.
  def self.generation_config(ai_template, json: AiGuardConfig.for_template(ai_template.name)[:format] == "json")
    config = { maxOutputTokens: ai_template.max_output_tokens.to_i, temperature: ai_template.temperature.to_f }
    if ai_template.model.to_s.start_with?("gemini-2.5")
      budget = THINKING_BUDGET
      budget = [budget, 128].max if budget >= 0 && ai_template.model.to_s.include?("pro") # pro can't turn thinking off
      config[:thinkingConfig]  = { thinkingBudget: budget }
      config[:maxOutputTokens] += budget if budget.positive?
    end
    config[:responseMimeType] = "application/json" if json
    config
  end

  def estimate_tokens(text)
    (text.to_s.length / 4.0).ceil
  end

  # Gemini Developer API paid-tier prices, in cents per 1M tokens (ai.google.dev/gemini-api/docs/pricing,
  # checked 2026-10-10). Output includes thinking tokens. Prompts here stay under the 200k-token tier.
  PRICES_CENTS_PER_MILLION = {
    "gemini-2.5-flash" => { input: 30.0,  output: 250.0 },
    "gemini-2.5-pro"   => { input: 125.0, output: 1000.0 }
  }.freeze

  def estimate_cost(prompt_tokens, response_tokens, model)
    rate = PRICES_CENTS_PER_MILLION.fetch(model.to_s, PRICES_CENTS_PER_MILLION["gemini-2.5-flash"])
    ((prompt_tokens.to_i * rate[:input]) + (response_tokens.to_i * rate[:output])) / 1_000_000.0
  end

  # Gemini bills thinking tokens as output, but reports them apart from the visible answer.
  def billed_output_tokens(body)
    usage = body["usageMetadata"] || {}
    return nil unless usage["candidatesTokenCount"] || usage["thoughtsTokenCount"]
    usage["candidatesTokenCount"].to_i + usage["thoughtsTokenCount"].to_i
  end

  def elapsed_ms(start)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
  end
end
