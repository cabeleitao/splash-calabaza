-- =====================================================================
-- Splash Calabaza — base de datos (proyecto Supabase "splash-calabaza")
-- Cuentas con usuario y contraseña (sin mail), amigos, partidas abiertas,
-- monedas y tienda. Todo se maneja con funciones: las tablas no se pueden
-- leer ni escribir directo desde el navegador.
-- =====================================================================
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.sc_users (
  id          uuid primary key default gen_random_uuid(),
  username    text not null unique check (username ~ '^[a-z0-9_]{3,15}$'),
  pass_hash   text not null,
  coins       integer not null default 0 check (coins >= 0),
  owned       text[] not null default '{}',
  fails       integer not null default 0,
  locked_until timestamptz,
  created_at  timestamptz not null default now()
);
create table if not exists public.sc_sessions (
  token_hash  text primary key,
  user_id     uuid not null references public.sc_users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  last_seen   timestamptz not null default now()
);
create table if not exists public.sc_friends (
  requester   uuid not null references public.sc_users(id) on delete cascade,
  addressee   uuid not null references public.sc_users(id) on delete cascade,
  status      text not null default 'pending' check (status in ('pending','accepted')),
  created_at  timestamptz not null default now(),
  primary key (requester, addressee),
  check (requester <> addressee)
);
create table if not exists public.sc_games (
  code        text primary key check (code ~ '^[a-z0-9]{4}$'),
  host        uuid not null references public.sc_users(id) on delete cascade,
  host_name   text not null,
  players     integer not null default 1,
  status      text not null default 'open' check (status in ('open','started')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists sc_sessions_user on public.sc_sessions(user_id);
create index if not exists sc_friends_addressee on public.sc_friends(addressee);
create index if not exists sc_games_host on public.sc_games(host);

-- Nadie accede a las tablas directamente (RLS sin políticas = todo cerrado).
alter table public.sc_users    enable row level security;
alter table public.sc_sessions enable row level security;
alter table public.sc_friends  enable row level security;
alter table public.sc_games    enable row level security;
revoke all on public.sc_users, public.sc_sessions, public.sc_friends, public.sc_games from anon, authenticated;

-- ---------- utilidades internas ----------
create or replace function public.sc__hash(p text) returns text
language sql immutable set search_path = public, extensions as $$
  select encode(extensions.digest(p, 'sha256'), 'hex');
$$;

create or replace function public.sc__uid(p_token text) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid;
begin
  if p_token is null or length(p_token) < 20 then return null; end if;
  update sc_sessions set last_seen = now() where token_hash = sc__hash(p_token) returning user_id into uid;
  return uid;
end $$;

create or replace function public.sc__new_session(p_user uuid) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare tok text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  insert into sc_sessions(token_hash, user_id) values (sc__hash(tok), p_user);
  return tok;
end $$;

create or replace function public.sc__profile(p_user uuid) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('id', id, 'username', username, 'coins', coins, 'owned', owned) from sc_users where id = p_user;
$$;

create or replace function public.sc__is_friend(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from sc_friends where status = 'accepted'
                 and ((requester = a and addressee = b) or (requester = b and addressee = a)));
$$;

-- ---------- cuentas ----------
create or replace function public.sc_username_free(p_username text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from sc_users where username = lower(trim(p_username)));
$$;

create or replace function public.sc_register(p_username text, p_password text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare u text := lower(trim(p_username)); new_id uuid;
begin
  if u !~ '^[a-z0-9_]{3,15}$' then return json_build_object('ok', false, 'error', 'usuario_invalido'); end if;
  if p_password is null or length(p_password) < 6 or length(p_password) > 72 then return json_build_object('ok', false, 'error', 'clave_invalida'); end if;
  if exists (select 1 from sc_users where username = u) then return json_build_object('ok', false, 'error', 'usuario_existe'); end if;
  insert into sc_users(username, pass_hash) values (u, extensions.crypt(p_password, extensions.gen_salt('bf', 8))) returning id into new_id;
  return json_build_object('ok', true, 'token', sc__new_session(new_id), 'user', sc__profile(new_id));
exception when unique_violation then
  return json_build_object('ok', false, 'error', 'usuario_existe');
end $$;

create or replace function public.sc_login(p_username text, p_password text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare r sc_users;
begin
  select * into r from sc_users where username = lower(trim(p_username));
  if r.id is null then return json_build_object('ok', false, 'error', 'datos_incorrectos'); end if;
  if r.locked_until is not null and r.locked_until > now() then return json_build_object('ok', false, 'error', 'bloqueado'); end if;
  if r.pass_hash <> extensions.crypt(coalesce(p_password, ''), r.pass_hash) then
    update sc_users set fails = fails + 1,
      locked_until = case when fails + 1 >= 8 then now() + interval '2 minutes' else null end
      where id = r.id;
    return json_build_object('ok', false, 'error', 'datos_incorrectos');
  end if;
  update sc_users set fails = 0, locked_until = null where id = r.id;
  delete from sc_sessions where user_id = r.id and last_seen < now() - interval '60 days';
  return json_build_object('ok', true, 'token', sc__new_session(r.id), 'user', sc__profile(r.id));
end $$;

create or replace function public.sc_logout(p_token text) returns void
language sql security definer set search_path = public, extensions as $$
  delete from sc_sessions where token_hash = sc__hash(p_token);
$$;

create or replace function public.sc_me(p_token text) returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := sc__uid(p_token);
begin
  if uid is null then return null; end if;
  return sc__profile(uid);
end $$;

-- ---------- amigos ----------
create or replace function public.sc_add_friend(p_token text, p_username text) returns text
language plpgsql security definer set search_path = public as $$
declare me uuid := sc__uid(p_token); other uuid;
begin
  if me is null then return 'sin_sesion'; end if;
  select id into other from sc_users where username = lower(trim(p_username));
  if other is null then return 'no_existe'; end if;
  if other = me then return 'sos_vos'; end if;
  if sc__is_friend(me, other) then return 'ya_amigos'; end if;
  if exists (select 1 from sc_friends where requester = other and addressee = me) then
    update sc_friends set status = 'accepted' where requester = other and addressee = me; return 'aceptado';
  end if;
  insert into sc_friends(requester, addressee) values (me, other) on conflict do nothing;
  return 'enviado';
end $$;

create or replace function public.sc_answer_friend(p_token text, p_from uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := sc__uid(p_token);
begin
  if me is null then return; end if;
  if p_accept then update sc_friends set status = 'accepted' where requester = p_from and addressee = me;
  else delete from sc_friends where requester = p_from and addressee = me; end if;
end $$;

create or replace function public.sc_remove_friend(p_token text, p_other uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := sc__uid(p_token);
begin
  if me is null then return; end if;
  delete from sc_friends where (requester = me and addressee = p_other) or (requester = p_other and addressee = me);
end $$;

create or replace function public.sc_friends(p_token text) returns json
language plpgsql security definer set search_path = public as $$
declare me uuid := sc__uid(p_token);
begin
  if me is null then return null; end if;
  return json_build_object(
    'friends',  coalesce((select json_agg(json_build_object('id', u.id, 'name', u.username) order by u.username) from sc_friends f join sc_users u on u.id = case when f.requester = me then f.addressee else f.requester end where f.status = 'accepted' and me in (f.requester, f.addressee)), '[]'::json),
    'incoming', coalesce((select json_agg(json_build_object('id', u.id, 'name', u.username)) from sc_friends f join sc_users u on u.id = f.requester where f.status = 'pending' and f.addressee = me), '[]'::json),
    'sent',     coalesce((select json_agg(json_build_object('id', u.id, 'name', u.username)) from sc_friends f join sc_users u on u.id = f.addressee where f.status = 'pending' and f.requester = me), '[]'::json));
end $$;

create or replace function public.sc_pending_count(p_token text) returns integer
language plpgsql security definer set search_path = public as $$
declare me uuid := sc__uid(p_token);
begin
  if me is null then return 0; end if;
  return (select count(*) from sc_friends where addressee = me and status = 'pending');
end $$;

-- ---------- monedas y tienda ----------
create or replace function public.sc_add_coins(p_token text, p_amount integer) returns integer
language plpgsql security definer set search_path = public as $$
declare me uuid := sc__uid(p_token); total integer;
begin
  if me is null or p_amount is null or p_amount < 0 or p_amount > 1000 then return null; end if;
  update sc_users set coins = coins + p_amount where id = me returning coins into total;
  return total;
end $$;

create or replace function public.sc_buy(p_token text, p_item text) returns json
language plpgsql security definer set search_path = public as $$
declare me uuid := sc__uid(p_token); price integer; r sc_users;
begin
  if me is null then return json_build_object('ok', false, 'error', 'sin_sesion'); end if;
  price := case p_item
    when 'char:zapallito' then 150  when 'char:estrella' then 150
    when 'hammer:caramelo' then 40  when 'hammer:hielo' then 50
    when 'hammer:dorado' then 60    when 'hammer:arcoiris' then 80
    when 'music:reggaeton' then 70 when 'music:pop' then 70 when 'music:chip' then 70
    else null end;
  if price is null then return json_build_object('ok', false, 'error', 'no_existe'); end if;
  select * into r from sc_users where id = me for update;
  if p_item = any(r.owned) then return json_build_object('ok', false, 'error', 'ya_lo_tenes'); end if;
  if r.coins < price then return json_build_object('ok', false, 'error', 'faltan_monedas'); end if;
  update sc_users set coins = coins - price, owned = array_append(owned, p_item) where id = me returning * into r;
  return json_build_object('ok', true, 'coins', r.coins, 'owned', r.owned);
end $$;

-- ---------- partidas abiertas (solo las ven los amigos del anfitrión) ----------
create or replace function public.sc_publish_game(p_token text, p_code text, p_players integer, p_status text) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := sc__uid(p_token); nm text;
begin
  if me is null then return; end if;
  if p_status = 'delete' then delete from sc_games where code = lower(p_code) and host = me; return; end if;
  if p_status not in ('open','started') then return; end if;
  select username into nm from sc_users where id = me;
  delete from sc_games where host = me and code <> lower(p_code);
  insert into sc_games(code, host, host_name, players, status, updated_at)
    values (lower(p_code), me, nm, greatest(1, least(4, coalesce(p_players, 1))), p_status, now())
    on conflict (code) do update set players = excluded.players, status = excluded.status, updated_at = now()
    where sc_games.host = me;
end $$;

create or replace function public.sc_open_games(p_token text) returns json
language plpgsql security definer set search_path = public as $$
declare me uuid := sc__uid(p_token);
begin
  if me is null then return '[]'::json; end if;
  delete from sc_games where updated_at < now() - interval '2 hours';
  return coalesce((select json_agg(json_build_object('code', code, 'host_name', host_name, 'players', players) order by created_at desc)
    from sc_games where status = 'open' and host <> me and updated_at > now() - interval '30 minutes' and sc__is_friend(me, host)), '[]'::json);
end $$;

-- ---------- permisos: el navegador solo puede llamar a estas funciones ----------
revoke all on function public.sc__hash(text), public.sc__uid(text), public.sc__new_session(uuid), public.sc__profile(uuid), public.sc__is_friend(uuid, uuid) from public, anon, authenticated;
grant execute on function
  public.sc_username_free(text), public.sc_register(text, text), public.sc_login(text, text), public.sc_logout(text), public.sc_me(text),
  public.sc_add_friend(text, text), public.sc_answer_friend(text, uuid, boolean), public.sc_remove_friend(text, uuid), public.sc_friends(text), public.sc_pending_count(text),
  public.sc_add_coins(text, integer), public.sc_buy(text, text), public.sc_publish_game(text, text, integer, text), public.sc_open_games(text)
  to anon, authenticated;
