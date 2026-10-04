module Evals
  module Adapters
    # Default adapter: one GeminiService call for one AiTemplate.
    # Agent apps add their own adapter that runs the full loop and returns a
    # tool-call trace ([{ tool:, args: }]) for the A and F layer checks.
    class Template
      def initialize(template_name)
        @template_name = template_name
      end

      def call(variables:, user:)
        Result.new(output: GeminiService.generate(template: @template_name, variables: variables, user: user), trace: [])
      end
    end
  end
end
