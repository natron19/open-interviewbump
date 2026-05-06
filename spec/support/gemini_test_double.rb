module GeminiTestDouble
  def gemini_returns(text = "Stubbed AI response.")
    allow(GeminiService).to receive(:generate).and_return(text)
  end

  def gemini_raises(error_class, message = "Stubbed error")
    allow(GeminiService).to receive(:generate).and_raise(error_class, message)
  end
end

RSpec.configure do |config|
  config.include GeminiTestDouble
end
