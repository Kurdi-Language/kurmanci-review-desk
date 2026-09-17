# Kurmancî Review Desk

A small website where invited reviewers sign in and record human decisions on Kurmancî vocabulary candidates. Static site on GitHub Pages, database and login on Supabase. Both are free; no domain, no card.

- Site: `https://kurdi-language.github.io/kurmanci-review-desk/` (after step 3)
- Candidates: `queue-hunspell-kuwiki-002.js` (current batch; `queue-hunspell-kuwiki-001.js` is the completed first batch), generated from the `kurmanci` repo (`scripts/review-desk/build_hunspell_queue.py`)
- Decisions: stored in Supabase, exported as JSON, merged into `data/review-decisions/…/decisions.jsonl` with `scripts/review-desk/merge_review_desk_export.py`

Nothing in this site makes a linguistic decision. It only records what a signed-in human chose, stamped server-side with their reviewer handle, and keeps every overwrite and delete in a history table.

## One-time setup (about 15 minutes)

### 1. Create the free database (Supabase)

1. Go to https://supabase.com, sign up (GitHub login works), click **New project**. Name it `kurmanci-review`, pick the EU region, set a database password (keep it somewhere safe), plan **Free**. Wait until the project is ready.
2. Left menu → **SQL Editor** → **New query**. Paste the whole content of `supabase/schema.sql` and click **Run**. It should finish without errors.
3. Left menu → **Authentication** → **Sign In / Providers** → **Email**: leave Email enabled, turn **off** “Allow new users to sign up” (only people you invite can get in), turn **off** “Confirm email” is not needed. Save.
4. Left menu → **Authentication** → **URL Configuration**: set **Site URL** to `https://kurdi-language.github.io/kurmanci-review-desk/` and add the same URL under **Redirect URLs**. Save.
5. Left menu → **Project Settings** → **API**: copy **Project URL** and the **anon public** key.

### 2. Put the two values into the site

Open `config.js` and replace the two placeholders with the Project URL and the anon key. The anon key is designed to be public; access is controlled by the rules in `schema.sql`.

### 3. Publish the site (GitHub Pages)

1. On GitHub, in the `Kurdi-Language` organization, create a new **public** repository named `kurmanci-review-desk` (no README, no license; the folder already has everything).
2. In this folder run:

   ```bash
   git remote add origin git@github.com:Kurdi-Language/kurmanci-review-desk.git
   git push -u origin main
   ```

3. In the repository: **Settings** → **Pages** → Source: **Deploy from a branch**, Branch: **main**, Folder: **/ (root)** → Save. After a minute the site is live at `https://kurdi-language.github.io/kurmanci-review-desk/`.

### 4. Invite reviewers

Supabase → **Authentication** → **Users** → **Invite user** → type their email. They receive an email; the link opens the site, where they choose a reviewer handle and a password. Invite yourself first. (Supabase's built-in mailer allows only a few emails per hour, which is fine for invitations.)

## Daily use

- Reviewers sign in with email and password, claim a block of 50 words, and press **1–5**. Reject requires a reason. Everyone sees everyone's progress live.
- **Export decisions** downloads a JSON file with `review-decision-v1` records for the whole queue.
- In the `kurmanci` repo:

  ```bash
  python3 scripts/review-desk/merge_review_desk_export.py ~/Downloads/hunspell-kuwiki-001-decisions-YYYY-MM-DD.json          # dry run
  python3 scripts/review-desk/merge_review_desk_export.py ~/Downloads/hunspell-kuwiki-001-decisions-YYYY-MM-DD.json --apply
  cargo run -p kurmanci-data-builder -- validate-review-decisions kurdish-hunspell-kmr
  cargo run -p kurmanci-data-builder -- build-pack reviewed
  ```

## Notes

- Free Supabase projects pause after a week without traffic; the dashboard shows a **Restore** button and the site works again within a minute. Data is kept.
- To load the next queue, generate a new `queue-*.js` file from the repo, point the `<script src>` in `index.html` at it, commit, push. Decisions are keyed by queue id, so old queues stay intact.
- Reviewer handles are permanent by design. If someone needs a different one, change it in Supabase → Table Editor → `reviewers`.
