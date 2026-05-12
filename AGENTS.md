# AGENTS.md

Guidance for AI agents working in this repository. Read this before making changes.

## Project

Panorama is a Rails 8.1 app whose goal is to let a user upload a sequence of overlapping photos and stitch them into a 360° equirectangular panorama. The full product spec — domain model, statuses, validation rules, UI flow, error classes, phasing — lives in `docs/360-photo-mvp-claude-code-spec.md`. Treat that file as the source of truth for product scope and naming; this file is only about how to work in the codebase.

The repo currently contains only the Rails scaffold + the spec — there is no domain code yet. Phase 1 / Phase 2 of the spec (skeleton workflow + background job with a fake stitcher) are the starting point.

## Stack

- Ruby 3.4.2, Rails 8.1, SQLite (`storage/*.sqlite3`)
- Hotwire (Turbo + Stimulus) via importmap, Tailwind CSS, Propshaft
- Solid Queue / Solid Cache / Solid Cable (DB-backed, no Redis)
- Active Storage for image uploads and the final panorama output
- Kamal + Thruster for deploy; Docker for production image

## Commands

Setup and dev:
- `bin/setup` — install gems, prepare DB, clear logs, then start the dev server
- `bin/setup --skip-server` — same but don't start the server
- `bin/dev` — start the dev server (uses `Procfile.dev`: `rails server` + `tailwindcss:watch`)
- `bin/rails db:prepare` / `bin/rails db:reset`

Tests:
- `bin/rails test` — full unit/integration suite (parallelized, fixtures auto-loaded — see `test/test_helper.rb`)
- `bin/rails test test/models/foo_test.rb` — single file
- `bin/rails test test/models/foo_test.rb:42` — single test at line 42
- `bin/rails test:system` — system tests (Capybara + Selenium)

Lint & security:
- `bin/rubocop` — style (rubocop-rails-omakase)
- `bin/brakeman` — static security analysis
- `bin/bundler-audit` — gem CVE audit
- `bin/importmap audit` — JS dependency audit

CI mirror:
- `bin/ci` — runs setup, rubocop, all security scans, tests, and a seed replant (see `config/ci.rb`). Run this before pushing if you want to mirror what GitHub Actions does (`.github/workflows/ci.yml`).

Background jobs:
- `bin/jobs` — run Solid Queue workers locally when exercising `StitchPanoramaJob` (or similar). Not in `Procfile.dev`; start it in a separate terminal.

## Architecture notes (read these before designing new code)

**Stitching is the core domain and MUST stay isolated.** The spec mandates a `PanoramaStitcher` abstraction with concrete implementations (`FakePanoramaStitcher` first, then `HuginPanoramaStitcher`). Controllers and views never call stitching tools directly — they enqueue a job, which calls the stitcher. Build this seam early; don't shortcut it.

**Two parallel state machines.** `PanoramaProject#status` (`draft → uploaded → validating → ready_to_process → processing → completed | failed`) is the user-facing lifecycle. A `StitchingJob`/`ProcessingLog` record (per spec) captures per-attempt diagnostics (`stdout`, `stderr`, `exit_code`). Keep them separate — the project's status is "where the user is," the job log is "what happened in this attempt."

**Production uses four SQLite databases** (see `config/database.yml`): `primary`, `cache`, `queue`, `cable`. Migrations for the non-primary ones go in `db/cache_migrate`, `db/queue_migrate`, `db/cable_migrate` — Rails will not auto-route a migration to them.

**Image pipeline workspace.** The spec defines `/tmp/panorama_projects/:project_id/{input,output,logs}` as the staging area for downloading Active Storage blobs, running the stitcher, and capturing logs before re-attaching the output. Treat this temp layout as part of the contract — tests and the real Hugin pipeline both depend on it.

**Phase ordering matters.** Per the spec, ship Phases 1–2 (UI + job + fake stitcher) end-to-end *before* integrating Hugin. Resist the urge to wire real CLI tools until the workflow round-trips with the fake.

## Conventions

- Style follows `rubocop-rails-omakase` (`.rubocop.yml`). Don't disable cops to silence warnings — fix the code.
- JS is importmap-based (`config/importmap.rb`, `app/javascript/controllers/`). No bundler, no npm install. Pin new packages with `bin/importmap pin <name>`.
- Tailwind is compiled by `tailwindcss-rails`; `bin/dev` runs the watcher.
- Fixtures are auto-loaded for every test (`fixtures :all` in `test_helper.rb`). Tests are parallelized — don't rely on global mutable state.
- The 360 viewer is browser-side (Three.js / Marzipano / Photo Sphere Viewer per spec). Pin via importmap; do not introduce a JS bundler.

## Things not to do

- Don't build a custom CV stitching algorithm — the spec is explicit. Shell out to Hugin behind the abstraction.
- Don't expose raw stitcher stdout/stderr to end users. Persist logs; show friendly errors.
- Don't add Redis or another job backend — Solid Queue is the choice.
- Don't replace SQLite with Postgres "to be safe" — the production deploy is built around SQLite + Litestream-style persistent volumes (`config/deploy.yml`).
