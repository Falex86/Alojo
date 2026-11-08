create schema if not exists ajolo_private;
revoke all on schema ajolo_private from public, anon, authenticated;
grant usage on schema ajolo_private to authenticated;

create table ajolo_private.encounter_entries (
    match_id uuid not null,
    user_id uuid not null references auth.users(id) on delete cascade,
    pet_id uuid not null,
    opponent_id uuid not null,
    pet jsonb not null,
    moves text[],
    receipt jsonb,
    created_at timestamptz not null default now(),
    primary key (match_id, user_id),
    unique (match_id, pet_id)
);
create index encounter_entries_user_id_idx on ajolo_private.encounter_entries (user_id);
alter table ajolo_private.encounter_entries enable row level security;

create table ajolo_private.breeding_claims (
    pet_id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    match_id uuid not null
);
create index breeding_claims_user_id_idx on ajolo_private.breeding_claims (user_id);
alter table ajolo_private.breeding_claims enable row level security;

create function ajolo_private.submit_encounter(p_match uuid, p_own uuid, p_partner uuid, p_moves text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    uid uuid := auth.uid();
    my_life jsonb;
    peer_life jsonb;
    a ajolo_private.encounter_entries;
    b ajolo_private.encounter_entries;
    my_score integer := 0;
    peer_score integer := 0;
    my_status text;
    peer_status text;
    result jsonb;
    other_result jsonb;
    unavailable jsonb := jsonb_build_object('id', p_match, 'status', 'unavailable');
begin
    if uid is null or p_match is null or p_own is null or p_partner is null or p_own = p_partner then
        return unavailable;
    end if;
    if p_moves is not null and (
        cardinality(p_moves) <> 3 or array_position(p_moves, null) is not null or
        not (p_moves <@ array['dash', 'guard', 'splash'])
    ) then
        return unavailable;
    end if;

    perform pg_advisory_xact_lock(hashtextextended(p_match::text, 42001));
    select * into a from ajolo_private.encounter_entries where match_id = p_match and user_id = uid;
    if found then
        if a.pet_id <> p_own or a.opponent_id <> p_partner or a.moves is distinct from p_moves then
            return unavailable;
        end if;
        if a.receipt is not null then return a.receipt; end if;
        if a.created_at < now() - interval '20 minutes' then return unavailable; end if;
    else
        select journal->'life' into my_life from public.ajolo_accounts where user_id = uid;
        if (my_life->>'id')::uuid is distinct from p_own or
           coalesce(my_life->>'sex', '') not in ('male', 'female') or
           coalesce(my_life->>'stage', '') in ('', 'Huevo', 'Falleció') then
            return unavailable;
        end if;
        if p_moves is null and (my_life->>'stage' <> 'Adulto' or my_life->'offspring' is not null) then
            return unavailable;
        end if;
        if p_moves is not null and (my_life->>'sex' <> 'male' or my_life#>>'{health,recoveryAt}' is not null) then
            return unavailable;
        end if;

        insert into ajolo_private.encounter_entries (match_id, user_id, pet_id, opponent_id, pet, moves)
        values (p_match, uid, p_own, p_partner, jsonb_build_object(
            'id', p_own, 'name', my_life->'name', 'sex', my_life->'sex', 'species', my_life->'species',
            'traits', my_life->'genes', 'parents', my_life#>'{origin,parents}', 'generation', my_life->'generation'
        ), p_moves)
        on conflict do nothing
        returning * into a;
        if not found then return unavailable; end if;
    end if;

    select * into b from ajolo_private.encounter_entries
    where match_id = p_match and pet_id = p_partner and opponent_id = p_own and user_id <> uid
      and created_at >= now() - interval '20 minutes';
    if not found then return jsonb_build_object('id', p_match, 'status', 'waiting'); end if;
    if b.receipt is not null then return unavailable; end if;

    my_status := 'unavailable';
    peer_status := 'unavailable';

    if a.moves is null and b.moves is null and a.pet->>'sex' <> b.pet->>'sex'
       and not exists (select 1 from jsonb_array_elements_text(coalesce(nullif(a.pet->'parents', 'null'::jsonb), '[]'::jsonb)) x
                       where x.value::uuid = b.pet_id)
       and not exists (select 1 from jsonb_array_elements_text(coalesce(nullif(b.pet->'parents', 'null'::jsonb), '[]'::jsonb)) x
                       where x.value::uuid = a.pet_id)
       and not exists (
            select 1 from jsonb_array_elements_text(coalesce(nullif(a.pet->'parents', 'null'::jsonb), '[]'::jsonb)) x
            join jsonb_array_elements_text(coalesce(nullif(b.pet->'parents', 'null'::jsonb), '[]'::jsonb)) y
              on x.value::uuid = y.value::uuid
       ) then
        select journal->'life' into my_life from public.ajolo_accounts where user_id = a.user_id;
        select journal->'life' into peer_life from public.ajolo_accounts where user_id = b.user_id;
        if (my_life->>'id')::uuid = a.pet_id and (peer_life->>'id')::uuid = b.pet_id
           and my_life->>'stage' = 'Adulto' and peer_life->>'stage' = 'Adulto'
           and my_life->'offspring' is null and peer_life->'offspring' is null then
            begin
                insert into ajolo_private.breeding_claims(pet_id, user_id, match_id)
                select v.pet_id, v.user_id, p_match
                from (values (a.pet_id, a.user_id), (b.pet_id, b.user_id)) as v(pet_id, user_id)
                order by v.pet_id;
                my_status := 'bred';
                peer_status := 'bred';
            exception when unique_violation then
                my_status := 'unavailable';
                peer_status := 'unavailable';
            end;
        end if;
    elsif a.moves is not null and b.moves is not null
          and a.pet->>'sex' = 'male' and b.pet->>'sex' = 'male' then
        for i in 1..3 loop
            if a.moves[i] <> b.moves[i] then
                if (a.moves[i], b.moves[i]) in (('dash', 'splash'), ('splash', 'guard'), ('guard', 'dash')) then
                    my_score := my_score + 1;
                else
                    peer_score := peer_score + 1;
                end if;
            end if;
        end loop;
        my_status := case when my_score > peer_score then 'won' when my_score < peer_score then 'lost' else 'draw' end;
        peer_status := case when peer_score > my_score then 'won' when peer_score < my_score then 'lost' else 'draw' end;
    end if;

    result := jsonb_build_object('id', p_match, 'status', my_status, 'partner', b.pet,
                                 'score', my_score, 'opponentScore', peer_score);
    other_result := jsonb_build_object('id', p_match, 'status', peer_status, 'partner', a.pet,
                                       'score', peer_score, 'opponentScore', my_score);
    update ajolo_private.encounter_entries set receipt = result
      where match_id = p_match and user_id = a.user_id;
    update ajolo_private.encounter_entries set receipt = other_result
      where match_id = p_match and user_id = b.user_id;
    return result;
end;
$$;

revoke all on function ajolo_private.submit_encounter(uuid, uuid, uuid, text[]) from public, anon, authenticated;
grant execute on function ajolo_private.submit_encounter(uuid, uuid, uuid, text[]) to authenticated;

create function public.ajolo_submit_encounter(p_match uuid, p_own uuid, p_partner uuid, p_moves text[])
returns jsonb language sql security invoker set search_path = ''
as $$ select ajolo_private.submit_encounter(p_match, p_own, p_partner, p_moves); $$;

revoke all on function public.ajolo_submit_encounter(uuid, uuid, uuid, text[]) from public, anon, authenticated;
grant execute on function public.ajolo_submit_encounter(uuid, uuid, uuid, text[]) to authenticated;
