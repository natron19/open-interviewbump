# Turbo & Stimulus Patterns Guide

Proven patterns for building reliable UI interactions in Rails 8 with importmap, Turbo, and Stimulus. This guide documents what works, what breaks, and why.

---

## Foundation Rules

**Standard Rails pages + minimal Stimulus.** All CRUD operations use conventional Rails pages. Stimulus handles only what HTML alone cannot: rich interactions, live updates, Editor.js integration.

### Approved Patterns
- Standard Rails forms with `form_with`, proper redirects
- Turbo Frames for in-page content switching without full page reloads
- Turbo Streams for targeted DOM updates from controller responses
- Stimulus for essential interactions: variable detection, sliders, editor initialization
- Progressive enhancement — core functionality must work without JavaScript

### Forbidden Patterns
- `onclick="someFunction()"` — use `data-action="click->controller#method"`
- `<script>` tags in views — use Stimulus controllers
- `addEventListener()` — use Stimulus actions
- Importing Bootstrap in Stimulus controllers — use `window.bootstrap`
- Complex JavaScript state management — use page-based Rails patterns

---

## 🚨 Critical: `update()` Not `replace()`

**`turbo_stream.replace()` destroys DOM elements and breaks Stimulus bindings after the first use.**

```ruby
# ❌ WRONG — works once, then silently fails forever
turbo_stream.replace("target-id", content)

# ✅ CORRECT — works every time, preserves Stimulus bindings
turbo_stream.update("target-id", content)
```

**Why `replace()` breaks:**
- Completely destroys the DOM element including all Stimulus controller bindings
- The second form submission finds no target element (it was replaced away)
- Chrome MutationObserver issues cause silent failures with no console errors

**Rule:** Use `update()` for all repeated operations — forms, AI results, flash messages. Use `replace()` only for one-time sections that will never be re-rendered.

### Multiple Stream Updates

```ruby
# Correct pattern for updating several regions at once
format.turbo_stream do
  render turbo_stream: [
    turbo_stream.update("result-container") { render partial: "result", locals: { result: @result } },
    turbo_stream.update("flash")            { render partial: "shared/flash" }
  ]
end
```

---

## Stimulus Controller Patterns

### Autoloading (Never Run `stimulus:manifest:update`)

The `index.js` Rails generates via `bin/rails stimulus:manifest:update` uses **relative imports that don't work with importmap** — all controllers silently fail.

**Required `app/javascript/controllers/index.js`:**

```javascript
// ✅ CORRECT — eager loading via importmap specifiers
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)
```

This auto-discovers every `*_controller.js` file. Never manually register controllers.

### Using Bootstrap Components in Stimulus

Never import Bootstrap in controllers — it breaks Turbo navigation.

```javascript
// ❌ WRONG — breaks Turbo
import 'bootstrap/js/dist/dropdown'

// ✅ CORRECT — Bootstrap loads via CDN, use window.bootstrap
export default class extends Controller {
  connect() {
    this.dropdown = new window.bootstrap.Dropdown(this.element)
  }

  disconnect() {
    this.dropdown?.dispose()
  }
}
```

Always dispose Bootstrap components in `disconnect()` to prevent memory leaks across Turbo navigations.

### Variable Inputs Controller (Admin Template Editor)

Detects `{{variable}}` placeholders in the prompt textarea and renders input fields dynamically.

```javascript
// app/javascript/controllers/variable_inputs_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["template", "inputs"]

  connect() {
    this.refresh()
  }

  refresh() {
    const text = this.templateTarget.value
    const vars = [...new Set([...text.matchAll(/\{\{(\w+)\}\}/g)].map(m => m[1]))]
    const existing = Object.fromEntries(
      [...this.inputsTarget.querySelectorAll("input[data-var]")].map(i => [i.dataset.var, i.value])
    )

    this.inputsTarget.innerHTML = vars.map(v => `
      <div class="mb-2">
        <label class="form-label small">${v}</label>
        <input type="text" name="variables[${v}]" class="form-control form-control-sm"
               data-var="${v}" value="${existing[v] || ''}">
      </div>
    `).join("")
  }
}
```

```erb
<div data-controller="variable-inputs">
  <textarea data-variable-inputs-target="template"
            data-action="input->variable-inputs#refresh"
            name="ai_template[user_prompt_template]">
    <%= @template.user_prompt_template %>
  </textarea>

  <div data-variable-inputs-target="inputs">
    <%# Populated dynamically %>
  </div>
</div>
```

### Temperature Slider Controller

```javascript
// app/javascript/controllers/temperature_slider_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["slider", "display"]

  connect() {
    this.update()
  }

  update() {
    this.displayTarget.textContent = this.sliderTarget.value
  }
}
```

```erb
<div data-controller="temperature-slider">
  <%= f.range_field :temperature, min: 0.0, max: 2.0, step: 0.1,
      data: { temperature_slider_target: "slider", action: "input->temperature-slider#update" } %>
  <span data-temperature-slider-target="display"><%= @template.temperature %></span>
</div>
```

---

## Turbo Frames

Use for replacing a section of a page without a full reload.

```erb
<%# Wrap the section in a named frame %>
<%= turbo_frame_tag "ai-result" do %>
  <%= render "result", result: @result %>
<% end %>

<%# Form targeting the frame %>
<%= form_with url: generate_path, data: { turbo_frame: "ai-result" } do |f| %>
  ...
<% end %>
```

The controller responds normally:

```ruby
def generate
  @result = GeminiService.generate(template: "...", variables: params[:variables])
  render :result   # renders app/views/.../result.html.erb inside the frame
end
```

---

## Flash Messages via Turbo Stream

The flash container has `id="flash"` so any Turbo Stream response can update it.

```ruby
# In a Turbo Stream response
turbo_stream.update("flash") do
  render partial: "shared/flash", locals: { flash: { notice: "Saved." } }
end
```

```erb
<%# app/views/shared/_flash.html.erb %>
<% flash.each do |type, message| %>
  <div class="alert alert-<%= flash_bootstrap_class(type) %> alert-dismissible fade show">
    <%= message %>
    <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
  </div>
<% end %>
```

---

## Delete Actions in Views

Use `link_to` with `data: { turbo_method: :delete }` — never `button_to` inside another form (causes CSRF conflicts).

```erb
<%= link_to "Delete", record_path(@record),
    data: { turbo_method: :delete, turbo_confirm: "Are you sure?" },
    class: "btn btn-sm btn-outline-danger" %>
```

---

## Status Tracking for Background Operations

Never use `Rails.cache` to track job status — Solid Queue workers run in separate processes and cache writes from workers are not guaranteed to reach the web process.

```ruby
# ❌ WRONG — status updates from workers vanish
Rails.cache.write("status_#{id}", "processing")

# ✅ CORRECT — database column shared across all processes
add_column :my_records, :status, :string, default: "pending"
```

Poll the status via a Turbo Frame or a simple JS `setInterval` calling a status endpoint that reads the database column.

---

## Editor.js Integration

Editor.js is the rich text editor for demo apps that need formatted content.

### Setup

Pin Editor.js and its tools via importmap:

```ruby
# config/importmap.rb
pin "@editorjs/editorjs", to: "https://cdn.jsdelivr.net/npm/@editorjs/editorjs@latest/dist/editorjs.umd.min.js"
pin "@editorjs/header",   to: "https://cdn.jsdelivr.net/npm/@editorjs/header@latest/dist/header.umd.min.js"
pin "@editorjs/list",     to: "https://cdn.jsdelivr.net/npm/@editorjs/list@latest/dist/list.umd.min.js"
```

### Stimulus Controller

```javascript
// app/javascript/controllers/editor_controller.js
import { Controller } from "@hotwired/stimulus"
import EditorJS from "@editorjs/editorjs"
import Header from "@editorjs/header"
import List from "@editorjs/list"

export default class extends Controller {
  static targets = ["input", "container"]
  static values = { data: Object, placeholder: { type: String, default: "Start writing..." } }

  connect() {
    this.editor = new EditorJS({
      holder: this.containerTarget,
      placeholder: this.placeholderValue,
      data: this.dataValue,
      tools: {
        header: Header,
        list: List
      },
      onChange: () => this.save()
    })
  }

  async save() {
    const data = await this.editor.save()
    this.inputTarget.value = JSON.stringify(data)
  }

  disconnect() {
    this.editor?.destroy()
  }
}
```

### View Partial

```erb
<%# app/views/shared/_editor_field.html.erb %>
<div data-controller="editor"
     data-editor-data-value="<%= form.object.send(field_name).to_json %>"
     data-editor-placeholder-value="<%= placeholder %>">
  <div data-editor-target="container" class="editor-wrapper border rounded p-2"></div>
  <%= form.hidden_field field_name, data: { editor_target: "input" } %>
</div>
```

### Spacing Fix

Editor.js has excessive vertical padding by default. Add to `application.css`:

```css
/* Editor.js spacing fix */
.editor-wrapper .ce-block,
.editor-wrapper .ce-paragraph {
  margin: 0 !important;
  padding: 0 !important;
  line-height: 1.4 !important;
}

.editor-wrapper .ce-paragraph + .ce-paragraph {
  margin-top: -0.5rem !important;
}
```

### Storing Content

- Store as `jsonb` column in PostgreSQL
- Add `description_text` method to models for plain-text extraction (AI prompts, search)

```ruby
def description_text
  return "" if description.blank?
  blocks = description.is_a?(String) ? JSON.parse(description)["blocks"] : description["blocks"]
  blocks&.map { |b| b.dig("data", "text") }&.compact&.join(" ") || ""
rescue JSON::ParserError
  ""
end
```

---

## Troubleshooting

### Stimulus controllers not connecting
1. Check `index.js` uses the eager-loading importmap pattern (never relative imports)
2. Verify `data-controller="name"` matches the filename `name_controller.js`
3. Hard-refresh to clear importmap cache
4. Check browser console for import errors

### Turbo Stream not updating
1. Verify the target `id` in the DOM matches the stream target
2. Confirm you're using `update()` not `replace()`
3. Check the controller action returns `format.turbo_stream` with the right content type

### Bootstrap dropdown/modal not working after Turbo navigation
1. Ensure you're using `window.bootstrap` in the Stimulus controller
2. Confirm `disconnect()` disposes of Bootstrap instances
3. Verify Bootstrap CDN script loads before Stimulus controllers in the layout

### Forms working once, then silently failing
Classic sign of `replace()` instead of `update()`. Change all `turbo_stream.replace` calls to `turbo_stream.update`.
