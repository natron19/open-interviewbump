module Evals
  module Adapters
    # Runs the prep-guide research agent the way PrepGuideJob does
    # (GeminiService.generate_with_tools with search_web via Perplexity and fetch_url),
    # synchronously and without a PrepSession record. Each tool call the model makes
    # becomes a trace entry for the A (max_tool_calls) and F (tools_subset_of,
    # called_tool) checks. Needs PERPLEXITY_API_KEY: without it search_web raises
    # GeminiError and the case is reported as an error.
    class InterviewbumpAgent
      def initialize(template_name)
        @template_name = template_name
      end

      def call(variables:, user:)
        trace  = []
        result = GeminiService.generate_with_tools(
          template:     @template_name,
          variables:    variables,
          tools:        tools,
          user:         user,
          on_tool_call: ->(name, args) { trace << { tool: name, args: args } }
        )
        Result.new(output: result[:text], trace: trace)
      end

      private

      # Same declarations and backends as PrepGuideJob, minus the PrepSession bookkeeping.
      def tools
        job = PrepGuideJob.new
        {
          "search_web" => {
            name: "search_web", description: "Search the web and return top results.",
            parameters: { type: "OBJECT", properties: { query: { type: "STRING", description: "The search query" } }, required: ["query"] },
            callable: ->(args) { PerplexitySearchService.search(args["query"]).slice(:answer, :sources) }
          },
          "fetch_url" => {
            name: "fetch_url", description: "Fetch the full text content of a URL.",
            parameters: { type: "OBJECT", properties: { url: { type: "STRING", description: "The URL to fetch" } }, required: ["url"] },
            callable: ->(args) { { content: job.send(:fetch_url_content, args["url"]) } }
          }
        }
      end
    end
  end
end
