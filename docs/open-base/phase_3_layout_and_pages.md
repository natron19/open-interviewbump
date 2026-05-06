# Phase 3 — Core Layout & Public Pages

**Goal:** The app looks and navigates like the boilerplate. Layout is complete. Home and dashboard pages exist. Admin base is wired up.

**Depends on:** Phase 2 complete (auth works, `current_user` available)

---

## 1. Application Layout

`app/views/layouts/application.html.erb`

### `<head>`

```html
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><%= ENV.fetch("APP_NAME", "Open Demo Starter") %></title>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= javascript_importmap_tags %>
</head>
```

### `<html>` element

```html
<html data-bs-theme="dark" lang="en">
```

### Navbar

```html
<nav class="navbar navbar-expand-lg bg-body-tertiary border-bottom">
  <div class="container">
    <!-- Brand -->
    <a class="navbar-brand fw-bold" href="/">
      <%= ENV.fetch("APP_NAME", "Open Demo Starter") %>
    </a>

    <!-- Right side -->
    <div class="ms-auto d-flex align-items-center gap-3">
      <% if signed_in? %>
        <div class="dropdown">
          <button class="btn btn-sm btn-outline-secondary dropdown-toggle" type="button" data-bs-toggle="dropdown">
            <%= current_user.first_name %>
          </button>
          <ul class="dropdown-menu dropdown-menu-end">
            <% if current_user.admin? %>
              <li><a class="dropdown-item" href="/admin">Admin</a></li>
              <li><hr class="dropdown-divider"></li>
            <% end %>
            <li>
              <%= button_to "Sign out", sign_out_path, method: :delete, class: "dropdown-item" %>
            </li>
          </ul>
        </div>
      <% else %>
        <%= link_to "Sign in", sign_in_path, class: "btn btn-sm btn-outline-light" %>
        <%= link_to "Sign up", sign_up_path, class: "btn btn-sm btn-primary" %>
      <% end %>
    </div>
  </div>
</nav>
```

### Flash Messages

Placed immediately after `<nav>`, before `<main>`. Must be Turbo-Stream-friendly (target `id="flash"`):

```html
<div id="flash" class="container mt-3">
  <% flash.each do |type, message| %>
    <div class="alert alert-<%= flash_bootstrap_class(type) %> alert-dismissible fade show" role="alert">
      <%= message %>
      <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
  <% end %>
</div>
```

Add helper `flash_bootstrap_class` in `ApplicationHelper`:
```ruby
def flash_bootstrap_class(type)
  { "notice" => "success", "alert" => "danger", "info" => "info" }.fetch(type, "secondary")
end
```

### `<main>`

```html
<main class="container py-4">
  <%= yield %>
</main>
```

### Footer

```html
<footer class="border-top mt-auto py-3 text-center text-muted small">
  <div class="container">
    <span><%= ENV.fetch("APP_TAGLINE", "") %></span>
    &nbsp;·&nbsp;
    <a href="/LICENSE" class="text-muted">MIT License</a>
    &nbsp;·&nbsp;
    Built with <a href="https://github.com/your-handle/open-base" class="text-muted">Open Demo Starter</a>
    <br>
    <span class="text-warning-emphasis">
      AI-generated content can be incorrect. Verify before acting.
    </span>
  </div>
</footer>
```

Set `<body class="d-flex flex-column min-vh-100">` so footer sticks to bottom.

---

## 2. `HomeController`

```ruby
class HomeController < ApplicationController
  skip_before_action :require_authentication

  def index
  end
end
```

`app/views/home/index.html.erb` — placeholder landing page:
- App name as hero heading
- Tagline from `ENV["APP_TAGLINE"]`
- Brief description from `ENV["APP_DESCRIPTION"]`
- CTA buttons: "Sign up free" and "Sign in"
- If already signed in, show "Go to dashboard" instead

---

## 3. `DashboardController`

```ruby
class DashboardController < ApplicationController
  def show
  end
end
```

`app/views/dashboard/show.html.erb`:
- Heading: "Welcome back, <%= current_user.first_name %>!"
- A Bootstrap card with placeholder text: "Your demo feature will live here."
- Subtext explaining what this boilerplate is (for visitors who clone and run it)

---

## 4. `Admin::BaseController`

```ruby
module Admin
  class BaseController < ApplicationController
    before_action :require_admin

    private

    def require_admin
      unless current_user&.admin?
        render file: Rails.public_path.join("404.html"), status: :not_found
      end
    end
  end
end
```

Key behavior: returns 404, not 403, so the admin namespace existence is not leaked to non-admins.

---

## 5. `HealthController`

```ruby
class HealthController < ApplicationController
  skip_before_action :require_authentication

  def llm
    # Stub for Phase 3; full Gemini ping implemented in Phase 4
    render json: { status: "not_configured", message: "Gemini not yet wired up" }, status: :ok
  end
end
```

---

## 6. Named Route Helpers

Ensure `config/routes.rb` defines named helpers used in views:

```ruby
get "/sign_in",  to: "sessions#new",     as: :sign_in
post "/sign_in", to: "sessions#create"
delete "/sign_out", to: "sessions#destroy", as: :sign_out
get "/sign_up",  to: "registrations#new",  as: :sign_up
post "/sign_up", to: "registrations#create"
```

---

## 7. Stimulus Controllers

No custom Stimulus controllers are needed at this phase. Confirm `app/javascript/controllers/index.js` is set up to autoload from the controllers directory (Rails 8 default).

---

## Acceptance Criteria

- [ ] `GET /` renders the landing page without requiring sign in
- [ ] Landing page shows `APP_NAME`, `APP_TAGLINE`, and `APP_DESCRIPTION` from env vars
- [ ] Signed-in user sees their first name in the navbar dropdown
- [ ] Signed-in admin user sees "Admin" link in the dropdown; non-admin does not
- [ ] `GET /dashboard` requires authentication; unauthenticated visit redirects to sign in
- [ ] Flash messages render with correct Bootstrap alert colors (green for notice, red for alert)
- [ ] Footer shows AI disclaimer on every page
- [ ] `GET /admin` returns 404 for non-admin users (not 403)
- [ ] `GET /admin` returns 404 for unauthenticated users (redirected to sign in first, then 404 on return)
- [ ] `GET /up/llm` returns 200 (stub response acceptable at this phase)
- [ ] No hardcoded app name, tagline, or description in any view — always read from env vars
