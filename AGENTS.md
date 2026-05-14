# NeuroBench — Agent Instructions

## Project Type
Static HTML/CSS/JS frontend (no framework, no build step) hosted on **GitHub Pages**.
Backend: **Supabase** (PostgreSQL + Edge Functions in Deno/TypeScript).

## Key URLs
- **Live**: https://moonishe.github.io/NB/
- **Repo**: https://github.com/Moonishe/NB
- **Supabase project**: `rwtogupudmlgkqtbhgup`

## Run Locally
```bash
npx serve .
# → http://localhost:3000
```
No `npm install`, no build. Just serve the root directory.

## Architecture
```
GitHub Pages (static)
  → Supabase JS client (@supabase/supabase-js)
    → PostgreSQL (data)
    → Edge Functions (Deno/TS): telegram-auth, admin-action
  → Telegram Login Widget (OAuth)
  → Cloudflare Turnstile (captcha)
```

## Key Files

### Entry Points
| File | Purpose |
|------|---------|
| `index.html` | Homepage + leaderboard |
| `svg.html` | SVG benchmark |
| `shader.html` | Shader benchmark |
| `voxel.html` | Voxel benchmark |
| `forum.html` | Forum |
| `profile.html` | User profile |
| `auth.html` | Telegram auth |
| `admin/index.html` | Admin panel |

### JS Modules (all vanilla, no bundler)
| File | Lines | Purpose |
|------|-------|---------|
| `js/config.js` | 4 | Supabase URL, anon key, Telegram bot, Turnstile key |
| `js/api.js` | 1266 | Supabase client wrapper (`Api.*`), RPC calls, CRUD |
| `js/auth.js` | 1819 | Telegram OAuth flow, Turnstile, invite codes |
| `js/leaderboard.js` | ~2000 | Leaderboard rendering, filters, search |
| `js/profile.js` | ~3000 | Profile page, achievements, stats |
| `js/forum.js` | ~1800 | Forum posts, comments, reactions |
| `js/navbar.js` | ~900 | Navigation, auth state, dropdowns |
| `js/main.js` | 66 | Visit tracking, search, GitHub commit SHA |
| `js/ascii-bg.js` | ~200 | ASCII art background animation |
| `js/title-scramble.js` | ~70 | Title text scramble effect |
| `js/shader.js` | ~120 | Shader benchmark logic |

### Supabase
| Path | Purpose |
|------|---------|
| `supabase/01-core.sql` | Core schema (users, models, scores) |
| `supabase/02-leaderboard.sql` | Leaderboard views & functions |
| `supabase/03-forum.sql` | Forum schema & RLS |
| `supabase/04-achievements.sql` | Achievements system |
| `supabase/05-admin.sql` | Admin functions |
| `supabase/06a-security-fixes.sql` | Security hardening |
| `supabase/06b-security-hardening.sql` | RLS, function security |
| `supabase/functions/telegram-auth/index.ts` | Telegram auth Edge Function |
| `supabase/functions/admin-action/index.ts` | Admin action Edge Function |

## Auth Flow
1. User clicks "Login with Telegram"
2. Telegram Login Widget opens → returns auth data
3. Frontend sends data to `telegram-auth` Edge Function
4. Edge Function verifies hash, creates/updates Supabase user
5. Session stored in localStorage under `neurobench-auth`

## Code Style
- Vanilla JS, no TypeScript on frontend
- IIFE modules: `const ModuleName = (() => { ... })();`
- Global `Api` object for all Supabase calls
- Tailwind CSS classes in HTML
- Dark terminal aesthetic (custom CSS in `css/style.css`)
- Comments in Russian (Cyrillic)

## CSS
- `css/style.css` (211 KB) — main stylesheet, dark theme
- `css/profile2.css` — profile-specific styles
- Cache busting: `?v=82` suffix on CSS links

## Deployment
- Push to `main` branch → GitHub Pages auto-deploys
- Edge Functions deployed via `supabase functions deploy`

## Git Conventions
- Commits in Russian/English mix
- Prefixes: `auth:`, `fix:`, `chore:`, `feat:`
- Co-Authored-By: Devin bot

## Important Notes
- No framework migration planned — keep it static
- XSS prevention: `_DANGEROUS_RE` regex in auth.js, sanitize functions
- RLS enabled on all Supabase tables
- Telegram auth uses HMAC-SHA256 verification server-side
- Turnstile is invisible captcha, site key in config.js

## Available MCP Servers
The following MCP servers are configured in Windsurf (`~/.codeium/windsurf/mcp_config.json`):

| Server | Type | Purpose |
|--------|------|---------|
| `supabase` | Remote (OAuth) | Direct DB queries, schema inspection, logs, migrations |
| `git` | Local (stdio) | Git history, blame, diff, log without shell commands |
| `sequential-thinking` | Local (stdio) | Multi-step reasoning for complex problems |
| `dsm` | Local (stdio) | Long-term persistent memory with hybrid search |
| `chrome-devtools` | Local (stdio) | Browser console, network, runtime debugging |
| `playwright` | Local (stdio) | Browser automation, UI testing |
| `context7` | Remote | Up-to-date library/framework documentation |
| `duckduckgo-search` | Local (stdio) | Web search |
| `fetch` | Local (stdio) | Fetch web pages as markdown |
| `filesystem` | Local (stdio) | File read/write operations |
| `github` | Remote | GitHub issues, PRs, repo management |
| `memory` | Local (stdio) | Key-value persistent memory |

## Session Ritual (CRITICAL — follow every session)

### Startup (first thing after greeting)
1. Check DSM state: call `dsm_info` to see how many segments are stored
2. If segments < 10 or no recent sync: call `dsm_sync` to index the project
3. Search DSM for recent context: `dsm_search("recent changes neurobench")`
4. Read `AGENTS.md` (this file) if not already loaded

### Before Important Changes (always)
Before any non-trivial edit (multi-file, auth, DB schema, security):
1. **Save context to DSM**: `dsm_write` with:
   - What files are being changed and why
   - Current state / problem being solved
   - `category_path`: `neurobench/session`
   - `importance`: 0.8+

### After Significant Changes (always)
1. **Save outcome to DSM**: `dsm_write` with:
   - What was done, which files changed
   - Any discoveries, gotchas, or decisions made
   - `category_path`: `neurobench/changes`
   - `importance`: 0.7+

### Before Session End
1. **Save session summary to DSM**: `dsm_write` with:
   - Key changes made this session
   - Unfinished tasks for next session
   - `category_path`: `neurobench/session`
   - `importance`: 0.9

## Pre-commit Hooks
Automatically run before every commit (via `pre-commit` framework, `.pre-commit-config.yaml`):
- `trailing-whitespace` — auto-fix trailing spaces
- `end-of-file-fixer` — auto-add final newline
- `detect-private-key` — block commits with keys/tokens
- `forbid-non-utf8` — block non-UTF-8 files (cp1251 prevention)
- `forbid-service-role` — block supabase service_role in JS/TS/configs

## Verification Commands
```bash
# Lint (none configured — vanilla JS, no tooling)
# Test locally
npx serve .
# → open http://localhost:3000
```
