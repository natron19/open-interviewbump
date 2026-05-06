# Pre-Publish Security Check

Copy and paste this prompt into Claude Code before making any demo app public on GitHub.

---

## Prompt

```
Perform a security review of this Rails app before it's published publicly on GitHub. Check every item below and report findings — safe or risky — with file path and line number for anything flagged.

**1. Hardcoded secrets**
Scan all files for hardcoded API keys, passwords, tokens, or secrets. Check: `.env`, `config/credentials.yml.enc`, `config/master.key`, `config/database.yml`, `config/secrets.yml`, `config/initializers/`, any `.key` files, and any file in `.kamal/`.

**2. Gitignore coverage**
Read `.gitignore` and confirm it excludes:
- `.env` and `.env.*`
- `config/master.key` and all `*.key` files
- `config/credentials.yml.enc`
- `log/` and `tmp/`
Report any of the above that are NOT covered.

**3. `.env.example`**
Read it and confirm every value is a placeholder (e.g. `your_key_here`), not a real value.

**4. `config/database.yml`**
Check for hardcoded username, password, or host. Production values should use `ENV.fetch(...)`.

**5. `db/seeds.rb`**
Check for hardcoded credentials beyond any intentional demo passwords that are documented in the README.

**6. `config/environments/production.rb`**
Check for hardcoded secrets. All sensitive values should use `ENV.fetch(...)`.

**7. Gemfile**
Confirm the only gem source is `https://rubygems.org`. Flag any private gem servers or `git:` sources pointing to private repos.

**8. README**
Check that it doesn't expose internal infrastructure details (internal URLs, server names, real email addresses, internal team names).

**9. Log and tmp files**
Confirm `log/` and `tmp/` contain no tracked files with sensitive content.

**10. Git history**
Run `git log --oneline` and check if any commit message suggests a secret was ever committed (e.g. "add API key", "fix credentials"). If so, flag it — the history would need to be scrubbed before publishing.

For each finding, state: file path, line number (if applicable), what the risk is, and what action to take. Fix any issues you can directly; flag anything that requires a manual step (like rotating a key).
```
