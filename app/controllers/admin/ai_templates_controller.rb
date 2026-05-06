module Admin
  class AiTemplatesController < Admin::BaseController
    def index
      @templates = AiTemplate.order(:name)
    end

    def edit
      @template = AiTemplate.find(params[:id])
    end

    def update
      @template = AiTemplate.find(params[:id])
      if @template.update(template_params)
        redirect_to admin_edit_ai_template_path(@template), notice: "Template saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def test
      @template = AiTemplate.find(params[:id])
      variables = params.fetch(:variables, {}).permit!.to_h.symbolize_keys

      result = GeminiService.generate(
        template:  @template.name,
        variables: variables,
        user:      current_user
      )

      log = LlmRequest.where(user: current_user, ai_template: @template)
                      .order(created_at: :desc).first

      render turbo_stream: turbo_stream.update("test-result",
        partial: "admin/ai_templates/test_result",
        locals:  { result: result, log: log }
      )

    rescue GeminiService::GeminiError => e
      render turbo_stream: turbo_stream.update("test-result",
        partial: "admin/ai_templates/test_error",
        locals:  { error: e.message }
      )
    end

    private

    def template_params
      params.require(:ai_template).permit(
        :system_prompt, :user_prompt_template, :model,
        :max_output_tokens, :temperature, :description, :notes
      )
    end
  end
end
