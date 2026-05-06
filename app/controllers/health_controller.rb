class HealthController < ApplicationController
  skip_before_action :require_authentication

  def llm
    ping_template = AiTemplate.find_by(name: "health_ping")

    if ping_template.nil?
      return render json: { status: "unconfigured",
                            message: "health_ping template not seeded" }, status: :ok
    end

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = GeminiService.generate(template: "health_ping", variables: {}, user: nil)
    duration_ms = elapsed_ms(start)

    render json: { status: "ok", response: result, duration_ms: duration_ms }

  rescue => e
    render json: { status: "error", message: e.message }, status: :service_unavailable
  end

  private

  def elapsed_ms(start)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
  end
end
