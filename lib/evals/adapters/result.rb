module Evals
  module Adapters
    # output: the final model text. trace: tool calls made along the way ([{ tool:, args: }]).
    Result = Struct.new(:output, :trace, keyword_init: true)
  end
end
