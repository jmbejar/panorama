# AGENTS.md

Guidance for AI agents working in this repository. Read this before making changes.

## Project

Panorama is a Rails 8.1 app whose goal is to let a user upload a sequence of overlapping photos and stitch them into a 360° equirectangular panorama. The full product spec — domain model, statuses, validation rules, UI flow, error classes, phasing — lives in `docs/360-photo-mvp-claude-code-spec.md`. Treat that file as the source of truth for product scope and naming; this file is only about how to work in the codebase.

Phases 1–3 of the spec are merged: the user-facing workflow, the background job with a swappable stitcher, and the Docker-based Hugin pipeline. The Fake stitcher remains the default (so tests + a fresh `bin/setup` pass with no host dependencies); the real engine is opt-in.

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
- `bin/jobs` — run Solid Queue workers locally when exercising `StitchPanoramaJob` (or similar). Not in `Procfile.dev`; start it in a separate terminal. In `development` the default queue adapter is `:async` (in-process), so for casual smoke tests you don't need to start a worker.

Real stitching engine (Hugin):
- `bin/panorama-hugin-build` — build the `panorama-hugin:latest` Docker image (debian-slim + hugin-tools + enblend + ImageMagick). Run once after clone, and again whenever you touch `docker/hugin/`.
- `PANORAMA_STITCHER=HuginPanoramaStitcher bin/rails server` — opt in to the real engine for a session. Default is `FakePanoramaStitcher`.
- `PANORAMA_KEEP_WORKSPACE=1` — leave `tmp/panorama_projects/:id/` on disk after a stitch (input/, output/, logs/) for debugging. Default behavior cleans it up.

## Architecture notes (read these before designing new code)

**Stitching is the core domain and MUST stay isolated.** The spec mandates a `PanoramaStitcher` abstraction with concrete implementations (`FakePanoramaStitcher` first, then `HuginPanoramaStitcher`). Controllers and views never call stitching tools directly — they enqueue a job, which calls the stitcher. Build this seam early; don't shortcut it.

**Two parallel state machines.** `PanoramaProject#status` (`draft → uploaded → validating → ready_to_process → processing → completed | failed`) is the user-facing lifecycle. A `StitchingJob`/`ProcessingLog` record (per spec) captures per-attempt diagnostics (`stdout`, `stderr`, `exit_code`). Keep them separate — the project's status is "where the user is," the job log is "what happened in this attempt."

**Production uses four SQLite databases** (see `config/database.yml`): `primary`, `cache`, `queue`, `cable`. Migrations for the non-primary ones go in `db/cache_migrate`, `db/queue_migrate`, `db/cable_migrate` — Rails will not auto-route a migration to them.

**Image pipeline workspace.** `PanoramaWorkspace` owns `tmp/panorama_projects/:id/{input,output,logs}` and is the contract between a stitcher and the rest of the app: input images come from Active Storage download, output is read back from `output/panorama.jpg`, and per-step logs from `logs/` are concatenated into `project.stitching_logs`. The fake stitcher doesn't use the workspace; the Hugin stitcher does. On macOS, Docker Desktop must have the repo path added to Settings → Resources → File Sharing for the bind mount to work.

**Hugin runs inside Docker, not on the host.** `HuginPanoramaStitcher` shells out to `docker run --rm -v <workspace>:/work panorama-hugin:latest`. The actual pipeline (`pto_gen → cpfind → cpclean → autooptimiser → pano_modify → hugin_executor`) lives in `docker/hugin/stitch.sh`. Per-step logs land in `/work/logs/NN_<step>.log` so a failed run still produces enough diagnostic info for the failed-state UI.

**Phase ordering matters.** Phases 1–3 are done. What's left per the spec: Phase 4 (360 viewer for completed panoramas) and Phase 5 (validation warnings, friendlier error messages, drag-to-reorder, upload progress). Keep the fake stitcher as the test default — never switch the test suite to the Hugin stitcher.

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
