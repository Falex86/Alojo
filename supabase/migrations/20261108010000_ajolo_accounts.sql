create table public.ajolo_accounts (
    user_id uuid primary key references auth.users (id) on delete cascade,
    journal jsonb not null check (jsonb_typeof(journal) = 'object'),
    revision bigint not null default 1 check (revision > 0),
    last_operation uuid not null,
    synced_at timestamptz not null default now()
);

alter table public.ajolo_accounts enable row level security;
revoke all on public.ajolo_accounts from public, anon, authenticated;
grant select, insert, update on public.ajolo_accounts to authenticated;

create policy ajolo_read_own on public.ajolo_accounts
    for select to authenticated using ((select auth.uid()) = user_id);
create policy ajolo_insert_own on public.ajolo_accounts
    for insert to authenticated with check ((select auth.uid()) = user_id);
create policy ajolo_update_own on public.ajolo_accounts
    for update to authenticated using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

create function public.ajolo_save(p_operation uuid, p_revision bigint, p_journal jsonb)
returns bigint
language sql
security invoker
set search_path = ''
as $$
    insert into public.ajolo_accounts as account (user_id, journal, last_operation)
    select auth.uid(), p_journal, p_operation
    where p_revision = 0 or exists (
        select 1 from public.ajolo_accounts
        where user_id = auth.uid()
    )
    on conflict (user_id) do update
    set journal = excluded.journal,
        last_operation = excluded.last_operation,
        revision = case when account.last_operation = excluded.last_operation
                        then account.revision else account.revision + 1 end,
        synced_at = now()
    where account.revision = p_revision or account.last_operation = p_operation
    returning revision;
$$;

revoke all on function public.ajolo_save(uuid, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.ajolo_save(uuid, bigint, jsonb) to authenticated;
