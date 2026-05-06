# Phase 5 — Admin Panel

**Goal:** The admin can inspect usage, view request logs, and iterate on AI templates in the browser without restarting the server.

**Depends on:** Phase 3 (Admin::BaseController, layout), Phase 4 (AiTemplate, LlmRequest models, GeminiService)

---

## 1. Controllers

### `Admin::DashboardController`

```ruby
module Admin
  class DashboardController < BaseController
    def show
      @total_users      = User.count
      @calls_today      = LlmRequest.today.count
      @calls_this_week  = LlmRequest.this_week.count
      @total_templates  = AiTemplate.count
      @recent_errors    = LlmRequest.failed.where(created_at: 24.hours.ago..Time.current).count
    end
  end
end
```

### `Admin::UsersController`

```ruby
module Admin
  class UsersController < BaseController
    def index
      @users = User.order(created_at: :desc)
    end
  end
end
```

Each user row needs: email, joined date, AI calls today, AI calls lifetime, last seen (last `LlmRequest` created_at or "Never").

Compute with a query, not N+1. Use a subquery or `includes` + group counts.

### `Admin::LlmRequestsController`

```ruby
module Admin
  class LlmRequestsController < BaseController
    def index
      @requests = LlmRequest.includes(:user, :ai_template)
                             .order(created_at: :desc)
                             .limit(100)
      @requests = @requests.where(status: params[:status]) if params[:status].present?
    end
  end
end
```

No pagination needed. 100-record cap is the spec.

### `Admin::AiTemplatesController`

```ruby
module Admin
  class AiTemplatesController < BaseController
    def index
      @templates = AiTemplate.order(:name)
    end

    def edit
      @template = AiTemplate.find(params[:id])
    end

    def update
      @template = AiTemplate.find(params[:id])
      if @template.update(template_params)
        redirect_to edit_admin_ai_template_path(@template), notice: "Template saved."
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
```

---

## 2. Views

### `admin/dashboard/show.html.erb`

- Four Bootstrap stat cards in a row:
  - Total Users
  - AI Calls Today
  - AI Calls This Week
  - Total Templates
- One additional "danger" card: Recent Errors (past 24h)
- Link: "View recent requests →" to `/admin/llm_requests`

### `admin/users/index.html.erb`

Responsive Bootstrap table:

| Column | Source |
|---|---|
| Email | `user.email` |
| Name | `user.name` |
| Joined | `user.created_at` (formatted) |
| AI Calls Today | `LlmRequest.where(user:).today.count` (precomputed) |
| AI Calls (Lifetime) | `LlmRequest.where(user:).count` (precomputed) |
| Last Seen | Most recent `LlmRequest` created_at, or "Never" |
| Admin? | Badge if `user.admin?` |

No edit, no delete. Read-only.

### `admin/llm_requests/index.html.erb`

- Status filter tabs or dropdown (All / success / error / timeout / gatekeeper_blocked / budget_exceeded)
- Table columns: timestamp, user email, template name, status (Bootstrap badge, color-coded), duration ms, tokens in, tokens out, cost estimate
- Each row is clickable — expands inline (Turbo Frame or collapse) to show the full prompt and response text for that request
- Status badge colors:
  - `success` → `bg-success`
  - `error` → `bg-danger`
  - `timeout` → `bg-warning`
  - `gatekeeper_blocked` → `bg-secondary`
  - `budget_exceeded` → `bg-secondary`
  - `pending` → `bg-info`

### `admin/ai_templates/index.html.erb`

Table: name, model, updated_at, "Edit" link for each row.

### `admin/ai_templates/edit.html.erb`

Two-column Bootstrap grid layout:

**Left column — editor (col-7):**
- `system_prompt` — `<textarea>` with 10 rows, monospace font
- `user_prompt_template` — `<textarea>` with 10 rows, monospace font; `{{variable}}` placeholders rendered in a distinct color via a small Stimulus controller
- `model` — `<select>` with options: `gemini-2.0-flash`, `gemini-1.5-pro`, `gemini-1.5-flash`
- `max_output_tokens` — number input (100–8192)
- `temperature` — range slider (0.0 to 2.0, step 0.1) with live value display
- `description` — text input
- `notes` — textarea (4 rows)
- Save button (`PATCH /admin/ai_templates/:id`)

**Right column — test panel (col-5):**
- Heading: "Test This Template"
- Variable inputs: auto-detected from `{{...}}` in the user prompt template, rendered as text inputs. Driven by a Stimulus controller that reads the template textarea and renders inputs dynamically.
- "Run Test" button → `POST /admin/ai_templates/:id/test` (Turbo Stream)
- `<div id="test-result">` — updated by Turbo Stream response
- Test result partial (`_test_result.html.erb`) shows:
  - Response text in a `<pre>` block
  - Token count (in / out)
  - Duration in ms
  - Cost estimate in cents

---

## 3. Stimulus Controllers

### `variable-inputs` controller

`app/javascript/controllers/variable_inputs_controller.js`

- Targets: the user prompt template textarea, the variable inputs container
- On `input` event in the textarea: extracts `{{variable}}` names via regex, re-renders input fields for any new variables, removes inputs for variables no longer present
- Stores prior test values in the controller's state so they persist while typing

### `temperature-slider` controller

`app/javascript/controllers/temperature_slider_controller.js`

- Displays the current slider value next to the range input, updating live on `input`

---

## 4. Test Result Partials

`app/views/admin/ai_templates/_test_result.html.erb`:

```erb
<div class="card mt-3">
  <div class="card-body">
    <h6 class="card-title text-success">Response</h6>
    <pre class="small text-light"><%= result %></pre>
    <% if log %>
      <hr>
      <div class="row text-muted small">
        <div class="col">Tokens in: <%= log.prompt_token_count %></div>
        <div class="col">Tokens out: <%= log.response_token_count %></div>
        <div class="col">Duration: <%= log.duration_ms %>ms</div>
        <div class="col">Cost: $<%= "%.6f" % (log.cost_estimate_cents.to_f / 100) %></div>
      </div>
    <% end %>
  </div>
</div>
```

`app/views/admin/ai_templates/_test_error.html.erb`:

```erb
<div class="alert alert-danger mt-3">
  <strong>Error:</strong> <%= error %>
</div>
```

---

## Acceptance Criteria

- [ ] `GET /admin` shows correct counts for users, calls today, calls this week, templates
- [ ] `GET /admin/users` shows user table with correct AI call counts (no N+1 queries)
- [ ] `GET /admin/llm_requests` shows last 100 requests in descending order
- [ ] Status filter on LLM requests works correctly
- [ ] Clicking a request row reveals the full prompt and response inline
- [ ] `GET /admin/ai_templates` lists all templates with edit links
- [ ] `GET /admin/ai_templates/:id/edit` renders the two-column editor
- [ ] Saving the template (`PATCH`) persists changes and redirects back with a success flash
- [ ] Variable inputs on the test panel auto-populate based on `{{...}}` in the user prompt template
- [ ] Clicking "Run Test" returns a Turbo Stream response with the result rendered in `#test-result`
- [ ] Test errors render the error partial in `#test-result` instead of crashing
- [ ] Temperature slider shows live value
- [ ] All admin routes return 404 for non-admin authenticated users
- [ ] All admin routes return redirect-to-sign-in for unauthenticated users
