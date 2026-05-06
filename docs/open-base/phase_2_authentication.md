# Phase 2 — Authentication

**Goal:** Users can sign up, sign in, sign out, and reset their password. No OAuth, no magic links, no email verification.

**Depends on:** Phase 1 complete (app boots, PostgreSQL connected, UUID extension enabled)

---

## 1. Migrations

### `CreateUsers`

```ruby
create_table :users, id: :uuid do |t|
  t.string  :email,           null: false
  t.string  :password_digest, null: false
  t.string  :name,            null: false
  t.boolean :admin,           default: false, null: false
  t.timestamps
end

add_index :users, :email, unique: true
```

### `CreatePasswordResets`

```ruby
create_table :password_resets, id: :uuid do |t|
  t.references :user,       null: false, foreign_key: true, type: :uuid
  t.string     :token,      null: false
  t.datetime   :expires_at, null: false
  t.datetime   :used_at
  t.timestamps
end

add_index :password_resets, :token, unique: true
```

---

## 2. Models

### `User`

```ruby
class User < ApplicationRecord
  has_secure_password

  before_save :downcase_email

  validates :email, presence: true, uniqueness: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name,  presence: true

  def first_name
    name.split.first
  end

  private

  def downcase_email
    self.email = email.downcase
  end
end
```

### `PasswordReset`

```ruby
class PasswordReset < ApplicationRecord
  belongs_to :user

  validates :token,      presence: true, uniqueness: true
  validates :expires_at, presence: true

  def expired?
    expires_at < Time.current
  end

  def used?
    used_at.present?
  end

  def valid_for_use?
    !expired? && !used?
  end
end
```

### `Current`

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :user
end
```

---

## 3. `ApplicationController`

```ruby
class ApplicationController < ActionController::Base
  before_action :require_authentication

  helper_method :current_user, :signed_in?

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def signed_in?
    current_user.present?
  end

  def require_authentication
    unless signed_in?
      redirect_to sign_in_path, alert: "Please sign in to continue."
    end
  end

  def require_admin
    render file: Rails.public_path.join("404.html"), status: :not_found unless current_user&.admin?
  end
end
```

- Set `Current.user = current_user` in a `before_action` (or override `process_action`).
- Handle `ActiveRecord::RecordNotFound` with flash + redirect to root.

---

## 4. Controllers

### `RegistrationsController`

- `new` — renders sign-up form
- `create` — creates user, signs them in (sets `session[:user_id]`), redirects to `/dashboard`
- Skips `require_authentication`
- Rate limited: 10 requests per minute per IP

### `SessionsController`

- `new` — renders sign-in form
- `create` — finds user by email, authenticates with `authenticate`, sets session, redirects to `/dashboard`; on failure re-renders with alert
- `destroy` — clears `session[:user_id]`, redirects to `/`
- Skips `require_authentication`
- Rate limited: 10 requests per minute per IP

### `PasswordsController`

- `new` — forgot password form (email input)
- `create` — finds user, generates a secure token, creates `PasswordReset`, sends `PasswordMailer#reset`, redirects with notice (always shows same message regardless of whether email was found, to avoid enumeration)
- `edit` — finds `PasswordReset` by token; redirects to `new` with alert if expired or used
- `update` — validates `PasswordReset`, updates user password, marks reset as used, signs user in, redirects to `/dashboard`
- Skips `require_authentication`

Token generation: `SecureRandom.urlsafe_base64(32)`
Expiry: `30.minutes.from_now`

---

## 5. Mailer

### `PasswordMailer`

```ruby
class PasswordMailer < ApplicationMailer
  def reset(user, token)
    @user  = user
    @token = token
    @url   = edit_password_url(token: token)
    mail to: @user.email, subject: "Reset your password"
  end
end
```

View: `app/views/password_mailer/reset.html.erb` — simple text with the reset link, expires-in note.

`letter_opener` configured in `config/environments/development.rb`:
```ruby
config.action_mailer.delivery_method = :letter_opener
config.action_mailer.perform_deliveries = true
```

---

## 6. Views

All forms use Bootstrap 5 card layout, dark mode compatible.

| View | Path |
|---|---|
| Sign up | `app/views/registrations/new.html.erb` |
| Sign in | `app/views/sessions/new.html.erb` |
| Forgot password | `app/views/passwords/new.html.erb` |
| Reset password | `app/views/passwords/edit.html.erb` |
| Password reset email | `app/views/password_mailer/reset.html.erb` |

Each form:
- Uses `form_with` (no remote by default)
- Displays `flash[:alert]` inline above the form
- Has a link to the sign-in page (and vice versa)

---

## 7. Rate Limiting

Use Rails 8 native `rate_limit` in each controller:

```ruby
rate_limit to: 10, within: 1.minute, by: -> { request.remote_ip },
           with: -> { redirect_to sign_in_path, alert: "Too many attempts. Try again in a minute." }
```

Apply to `RegistrationsController` and `SessionsController`.

---

## Acceptance Criteria

- [ ] User can sign up with name, email, and password; is redirected to `/dashboard` and greeted by first name
- [ ] Duplicate email shows a validation error on the form
- [ ] User can sign in with correct credentials and is redirected to `/dashboard`
- [ ] Invalid credentials show an alert, do not reveal whether the email exists
- [ ] User can sign out; session is cleared; redirected to `/`
- [ ] Forgot password form accepts any email without revealing whether it's registered
- [ ] Password reset email opens in browser via `letter_opener` with a valid reset link
- [ ] Expired reset token redirects to forgot-password with an alert
- [ ] Used reset token cannot be reused
- [ ] Unauthenticated visit to `/dashboard` redirects to `/sign_in`
- [ ] No plain-text passwords appear in logs or the database
