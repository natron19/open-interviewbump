# Phase 1 — Rails App Foundation

**Goal:** Stand up the app skeleton with correct tooling, no domain logic, no secrets in repo.

---

## 1. Generate the Rails App

```bash
rails new open-base \
  --database=postgresql \
  --asset-pipeline=sprockets \
  --skip-action-mailer \
  --skip-action-cable \
  --skip-action-text \
  --skip-active-storage \
  --skip-jbuilder \
  --javascript=importmap
```

- Enable UUID primary keys globally in `config/application.rb`:
  ```ruby
  config.generators do |g|
    g.orm :active_record, primary_key_type: :uuid
  end
  ```
- Add `enable_extension 'pgcrypto'` to the first migration (or an initializer migration).

---

## 2. Gemfile

Add the following gems:

```ruby
# AI
gem 'google-generative-ai'

# Env vars
gem 'dotenv-rails', groups: [:development, :test]

# Dev mail preview
gem 'letter_opener', group: :development

# Testing
group :test do
  gem 'rspec-rails'
  gem 'factory_bot_rails'
  gem 'capybara'
end
```

Remove unused default gems (jbuilder, etc.) that were skipped during generation.

---

## 3. Environment Variables

### `.env.example` (committed)

```
# App branding
APP_NAME="Open Demo Starter"
APP_TAGLINE="A Rails 8 + AI boilerplate"
APP_DESCRIPTION="Clone, run, and extend in under 30 minutes."

# Gemini
GEMINI_API_KEY=your_key_here

# AI operational settings
AI_CALLS_PER_USER_PER_DAY=50
AI_GLOBAL_TIMEOUT_SECONDS=15
```

### `.env` (gitignored, never committed)

Developer copies `.env.example` → `.env` and fills in real values.

---

## 4. `.gitignore`

Ensure these are present (in addition to Rails defaults):

```
.env
*.env.local
```

Verify `.env.example` is NOT in `.gitignore`.

---

## 5. Bootstrap 5 Dark Mode

- Add Bootstrap 5 via CDN in `app/views/layouts/application.html.erb` (or via importmap pin):
  ```
  pin "bootstrap", to: "https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"
  ```
- Add Bootstrap CSS link tag in the layout `<head>`.
- Set dark mode on the HTML element:
  ```html
  <html data-bs-theme="dark">
  ```

---

## 6. CSS — Accent Color Variables

Create `app/assets/stylesheets/application.css` with:

```css
@import url("https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css");

:root {
  --accent: #1d4ed8;
  --accent-hover: #1e40af;
}
```

No SCSS required. This is the single customization point per demo.

---

## 7. Routes Stub

`config/routes.rb` — define all routes from the PRD even if controllers do not exist yet (they will raise routing errors until controllers are added, which is acceptable at this phase):

```ruby
Rails.application.routes.draw do
  root "home#index"
  get  "/dashboard", to: "dashboard#show"

  get  "/sign_up",   to: "registrations#new"
  post "/sign_up",   to: "registrations#create"

  get    "/sign_in",  to: "sessions#new"
  post   "/sign_in",  to: "sessions#create"
  delete "/sign_out", to: "sessions#destroy"

  get   "/passwords/new",         to: "passwords#new"
  post  "/passwords",             to: "passwords#create"
  get   "/passwords/edit",        to: "passwords#edit"
  patch "/passwords/:token",      to: "passwords#update"

  namespace :admin do
    get  "/",                           to: "dashboard#show"
    get  "/users",                      to: "users#index"
    get  "/llm_requests",               to: "llm_requests#index"
    get  "/ai_templates",               to: "ai_templates#index"
    get  "/ai_templates/:id/edit",      to: "ai_templates#edit"
    patch "/ai_templates/:id",          to: "ai_templates#update"
    post "/ai_templates/:id/test",      to: "ai_templates#test"
  end

  get "/up/llm", to: "health#llm"
  get "/up",     to: "rails/health#show", as: :rails_health_check
end
```

---

## 8. Stimulus + Turbo

These are included by default in Rails 8 via importmap. Confirm `config/importmap.rb` pins `@hotwired/turbo-rails` and `@hotwired/stimulus`.

---

## Acceptance Criteria

- [ ] `bundle install` succeeds with no errors
- [ ] `rails db:create` creates the development and test databases
- [ ] `rails server` starts without errors
- [ ] `GET /` returns 200 (even if just the default Rails welcome page for now)
- [ ] No `.env` file committed to git
- [ ] `.env.example` is committed with all variable stubs, no real values
- [ ] Bootstrap dark mode class is present on `<html>` element in page source
- [ ] `--accent` CSS variable is defined in the stylesheet
