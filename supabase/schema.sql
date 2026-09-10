-- Kurmancî Review Desk — database schema, access rules, and audit triggers.
-- Run once in Supabase: SQL Editor → New query → paste → Run.
-- Candidates live in the static site; the database stores only human decisions,
-- block claims, and reviewer handles. Every decision is stamped server-side with
-- the signed-in user's id and handle, and every overwrite or delete is kept in history.

create table if not exists public.reviewers (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  handle     text not null unique check (handle ~ '^[a-z0-9][a-z0-9-]{1,39}$'),
  created_at timestamptz not null default now()
);

create table if not exists public.decisions (
  queue_id    text not null,
  target_id   text not null check (target_id ~ '^[0-9a-f]{64}$'),
  rank        integer not null,
  display     text not null,
  status      text not null check (status in ('approved','rejected','experimental','linguist','source')),
  note        text not null default '',
  reviewer_id uuid not null references auth.users(id),
  handle      text not null,
  decided_at  timestamptz not null default now(),
  primary key (queue_id, target_id)
);
create index if not exists decisions_queue_rank on public.decisions (queue_id, rank);

create table if not exists public.decision_history (
  id          bigserial primary key,
  queue_id    text not null,
  target_id   text not null,
  status      text not null,
  note        text not null,
  handle      text not null,
  reviewer_id uuid not null,
  decided_at  timestamptz not null,
  replaced_by text not null,
  action      text not null check (action in ('update','delete')),
  replaced_at timestamptz not null default now()
);

create table if not exists public.block_claims (
  queue_id   text not null,
  block_no   integer not null,
  handle     text not null,
  user_id    uuid not null references auth.users(id) on delete cascade,
  claimed_at timestamptz not null default now(),
  primary key (queue_id, block_no)
);

-- Server-side stamping: the client never chooses who a decision belongs to.
create or replace function public.stamp_decision() returns trigger
language plpgsql security definer set search_path = public as $$
declare h text;
begin
  select handle into h from public.reviewers where user_id = auth.uid();
  if h is null then raise exception 'Choose a reviewer handle before deciding.'; end if;
  new.reviewer_id := auth.uid();
  new.handle := h;
  new.decided_at := now();
  new.note := coalesce(new.note, '');
  if new.status = 'rejected' and length(trim(new.note)) = 0 then
    raise exception 'A rejection needs a reason.';
  end if;
  if tg_op = 'UPDATE' then
    insert into public.decision_history (queue_id, target_id, status, note, handle, reviewer_id, decided_at, replaced_by, action)
    values (old.queue_id, old.target_id, old.status, old.note, old.handle, old.reviewer_id, old.decided_at, h, 'update');
  end if;
  return new;
end $$;

create or replace function public.log_decision_delete() returns trigger
language plpgsql security definer set search_path = public as $$
declare h text;
begin
  select handle into h from public.reviewers where user_id = auth.uid();
  insert into public.decision_history (queue_id, target_id, status, note, handle, reviewer_id, decided_at, replaced_by, action)
  values (old.queue_id, old.target_id, old.status, old.note, old.handle, old.reviewer_id, old.decided_at, coalesce(h, 'unknown'), 'delete');
  return old;
end $$;

create or replace function public.stamp_claim() returns trigger
language plpgsql security definer set search_path = public as $$
declare h text;
begin
  select handle into h from public.reviewers where user_id = auth.uid();
  if h is null then raise exception 'Choose a reviewer handle before claiming a block.'; end if;
  new.user_id := auth.uid();
  new.handle := h;
  new.claimed_at := now();
  return new;
end $$;

drop trigger if exists decisions_stamp on public.decisions;
create trigger decisions_stamp before insert or update on public.decisions
  for each row execute function public.stamp_decision();
drop trigger if exists decisions_delete_log on public.decisions;
create trigger decisions_delete_log before delete on public.decisions
  for each row execute function public.log_decision_delete();
drop trigger if exists block_claims_stamp on public.block_claims;
create trigger block_claims_stamp before insert or update on public.block_claims
  for each row execute function public.stamp_claim();

-- Access rules: only signed-in (invited) users, and only through the triggers above.
alter table public.reviewers        enable row level security;
alter table public.decisions        enable row level security;
alter table public.decision_history enable row level security;
alter table public.block_claims     enable row level security;

drop policy if exists "reviewers: read"       on public.reviewers;
drop policy if exists "reviewers: create own" on public.reviewers;
create policy "reviewers: read"       on public.reviewers for select to authenticated using (true);
create policy "reviewers: create own" on public.reviewers for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "decisions: read"   on public.decisions;
drop policy if exists "decisions: insert" on public.decisions;
drop policy if exists "decisions: update" on public.decisions;
drop policy if exists "decisions: delete" on public.decisions;
create policy "decisions: read"   on public.decisions for select to authenticated using (true);
create policy "decisions: insert" on public.decisions for insert to authenticated with check (true);
create policy "decisions: update" on public.decisions for update to authenticated using (true) with check (true);
create policy "decisions: delete" on public.decisions for delete to authenticated using (true);

drop policy if exists "history: read" on public.decision_history;
create policy "history: read" on public.decision_history for select to authenticated using (true);

drop policy if exists "claims: read"   on public.block_claims;
drop policy if exists "claims: insert" on public.block_claims;
drop policy if exists "claims: update" on public.block_claims;
drop policy if exists "claims: delete" on public.block_claims;
create policy "claims: read"   on public.block_claims for select to authenticated using (true);
create policy "claims: insert" on public.block_claims for insert to authenticated with check (true);
create policy "claims: update" on public.block_claims for update to authenticated using (true) with check (true);
create policy "claims: delete" on public.block_claims for delete to authenticated using (true);

-- Live updates for everyone with the page open.
alter table public.decisions    replica identity full;
alter table public.block_claims replica identity full;
do $$ begin
  alter publication supabase_realtime add table public.decisions;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.block_claims;
exception when duplicate_object then null; end $$;

-- Handy export view (Table Editor → decisions_export → Export CSV / or used by the site).
create or replace view public.decisions_export as
  select queue_id, rank, target_id, display, status, note, handle, decided_at
  from public.decisions order by queue_id, rank;
