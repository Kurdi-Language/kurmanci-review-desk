-- Adds the project status "approved_with_metadata_change" (stored as 'metadata')
-- and a column for the corrected metadata. Run once in Supabase: SQL Editor → New query → paste → Run.
alter table public.decisions drop constraint if exists decisions_status_check;
alter table public.decisions add constraint decisions_status_check
  check (status in ('approved','metadata','rejected','experimental','linguist','source'));
alter table public.decisions add column if not exists meta jsonb;
alter table public.decision_history add column if not exists meta jsonb;

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
  if new.status = 'metadata' and (new.meta is null or coalesce(new.meta->>'display','') = '') then
    raise exception 'Approved with metadata change needs the corrected metadata.';
  end if;
  if new.status <> 'metadata' then new.meta := null; end if;
  if tg_op = 'UPDATE' then
    insert into public.decision_history (queue_id, target_id, status, note, handle, reviewer_id, decided_at, replaced_by, action, meta)
    values (old.queue_id, old.target_id, old.status, old.note, old.handle, old.reviewer_id, old.decided_at, h, 'update', old.meta);
  end if;
  return new;
end $$;

create or replace function public.log_decision_delete() returns trigger
language plpgsql security definer set search_path = public as $$
declare h text;
begin
  select handle into h from public.reviewers where user_id = auth.uid();
  insert into public.decision_history (queue_id, target_id, status, note, handle, reviewer_id, decided_at, replaced_by, action, meta)
  values (old.queue_id, old.target_id, old.status, old.note, old.handle, old.reviewer_id, old.decided_at, coalesce(h, 'unknown'), 'delete', old.meta);
  return old;
end $$;

drop view if exists public.decisions_export;
create view public.decisions_export as
  select queue_id, rank, target_id, display, status, note, meta, handle, decided_at
  from public.decisions order by queue_id, rank;
