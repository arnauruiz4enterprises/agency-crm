-- Agency CRM · Link Pages (páginas públicas de links con estadísticas)
-- Ejecútalo una vez en Supabase → SQL Editor → New query → Run. Se puede repetir sin romper nada.

-- 1. Contadores por página y día (sin datos personales: ni IP ni identificadores)
create table if not exists public.link_stats (
  slug     text not null,
  day      date not null default current_date,
  visits   integer not null default 0,
  clicks   integer not null default 0,
  clicks_b integer not null default 0,
  bots     integer not null default 0,
  primary key (slug, day)
);
alter table public.link_stats enable row level security;
drop policy if exists link_stats_admin on public.link_stats;
create policy link_stats_admin on public.link_stats for select to authenticated using (public.is_admin());

-- 2. Ajustes privados (clave secreta de Turnstile). Sin políticas: nadie la lee desde fuera.
create table if not exists public.link_config (k text primary key, v text);
alter table public.link_config enable row level security;

create or replace function public.link_set_config(p_k text, p_v text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'solo admin'; end if;
  if p_k not in ('turnstile_sitekey', 'turnstile_secret') then raise exception 'clave no válida'; end if;
  if p_v is null or p_v = '' then delete from public.link_config where k = p_k;
  else insert into public.link_config (k, v) values (p_k, p_v) on conflict (k) do update set v = excluded.v; end if;
end $$;
revoke all on function public.link_set_config(text, text) from public;
grant execute on function public.link_set_config(text, text) to authenticated;

create or replace function public.link_has_secret() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_admin() then jsonb_build_object(
    'sitekey', (select v from public.link_config where k = 'turnstile_sitekey'),
    'secret', exists (select 1 from public.link_config where k = 'turnstile_secret')) else null end;
$$;
revoke all on function public.link_has_secret() from public;
grant execute on function public.link_has_secret() to authenticated;

-- 3. Página publicada (solo lo visible; los destinos se entregan aparte si hay verificación)
create or replace function public.link_row(p_slug text) returns jsonb
language sql stable security definer set search_path = public as $$
  select data from public.docs
  where col = 'linkpages' and data->>'pub' = 'Published'
    and ((coalesce(p_slug, '') <> '' and lower(data->>'slug') = lower(p_slug))
      or (coalesce(p_slug, '') = '' and coalesce((data->>'main_page')::boolean, false)))
  limit 1;
$$;
revoke all on function public.link_row(text) from public;

create or replace function public.link_dest(d jsonb) returns jsonb
language sql immutable as $$
  select jsonb_build_object('dest', d->>'dest', 'dest_b', d->>'dest_b', 'split', d->'split',
    'buttons', coalesce(d->'buttons', '[]'::jsonb));
$$;

create or replace function public.link_page(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d jsonb; v boolean; r jsonb;
begin
  d := public.link_row(p_slug);
  if d is null then return null; end if;
  v := coalesce((d->>'verify')::boolean, false);
  r := jsonb_build_object('slug', d->>'slug', 'name', d->>'page_name', 'bio', d->>'bio', 'theme', d->>'theme',
    'online', d->'online', 'photo', d->>'photo', 'format', d->>'format', 'btn_text', d->>'btn_text',
    'btn_img', d->>'btn_img', 'verify', v,
    'sitekey', case when v then (select c.v from public.link_config c where c.k = 'turnstile_sitekey') end);
  if not v then r := r || public.link_dest(d); end if;
  return r;
end $$;
revoke all on function public.link_page(text) from public;
grant execute on function public.link_page(text) to anon, authenticated;

-- 4. Destinos tras la verificación humana (Cloudflare Turnstile, si está configurado)
create extension if not exists http with schema extensions;
create or replace function public.link_open(p_slug text, p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare d jsonb; sec text; res jsonb;
begin
  d := public.link_row(p_slug);
  if d is null then return null; end if;
  if coalesce((d->>'verify')::boolean, false) then
    select v into sec from public.link_config where k = 'turnstile_secret';
    if sec is not null then
      if coalesce(p_token, '') = '' then return jsonb_build_object('error', 'verify'); end if;
      select content::jsonb into res from extensions.http_post(
        'https://challenges.cloudflare.com/turnstile/v0/siteverify',
        'secret=' || extensions.urlencode(sec) || '&response=' || extensions.urlencode(p_token),
        'application/x-www-form-urlencoded');
      if not coalesce((res->>'success')::boolean, false) then return jsonb_build_object('error', 'verify'); end if;
    end if;
  end if;
  return public.link_dest(d);
end $$;
revoke all on function public.link_open(text, text) from public;
grant execute on function public.link_open(text, text) to anon, authenticated;

-- 5. Registrar visita / clic / bot (solo suma 1 al contador del día)
create or replace function public.link_hit(p_slug text, p_kind text) returns void
language plpgsql security definer set search_path = public as $$
declare d jsonb; s text;
begin
  if p_kind not in ('visit', 'click', 'click_b', 'bot') then return; end if;
  d := public.link_row(p_slug);
  if d is null then return; end if;
  s := lower(d->>'slug');
  insert into public.link_stats (slug, day, visits, clicks, clicks_b, bots)
  values (s, current_date, (p_kind = 'visit')::int, (p_kind in ('click', 'click_b'))::int, (p_kind = 'click_b')::int, (p_kind = 'bot')::int)
  on conflict (slug, day) do update set
    visits = link_stats.visits + excluded.visits, clicks = link_stats.clicks + excluded.clicks,
    clicks_b = link_stats.clicks_b + excluded.clicks_b, bots = link_stats.bots + excluded.bots;
end $$;
revoke all on function public.link_hit(text, text) from public;
grant execute on function public.link_hit(text, text) to anon, authenticated;
