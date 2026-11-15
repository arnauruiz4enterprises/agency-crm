-- Agency CRM · esquema de Supabase
-- Ejecútalo una sola vez en Supabase → SQL Editor → New query → Run.
-- Se puede volver a ejecutar sin romper nada.

-- 1. Perfiles: un perfil por cada persona con cuenta (admin o modelo)
create table if not exists public.profiles (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  email        text,
  display_name text,
  role         text not null default 'model' check (role in ('admin', 'model')),
  model_id     text,            -- id de la creadora que ve una cuenta de modelo
  created_at   timestamptz not null default now()
);

-- 2. Documentos del CRM: cuentas, contenido, plan, plantillas, propuestas...
create table if not exists public.docs (
  col        text not null,     -- colección: accounts, content, models, ...
  id         text not null,
  model      text,              -- creadora a la que pertenece el registro
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  primary key (col, id)
);
create index if not exists docs_model_idx on public.docs (model);
alter table public.docs replica identity full;

-- 3. Funciones de ayuda para las reglas
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where user_id = auth.uid() and role = 'admin');
$$;

create or replace function public.my_model() returns text
language sql stable security definer set search_path = public as $$
  select model_id from public.profiles where user_id = auth.uid() and role = 'model';
$$;

-- 4. Reglas de acceso (Row Level Security)
alter table public.profiles enable row level security;
alter table public.docs     enable row level security;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update on public.profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists profiles_admin_delete on public.profiles;
create policy profiles_admin_delete on public.profiles for delete to authenticated
  using (public.is_admin());

-- Admin: todo
drop policy if exists docs_admin on public.docs;
create policy docs_admin on public.docs for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Modelo: solo lee su contenido, sus propuestas, su ficha, tutoriales y ajustes
drop policy if exists docs_model_read on public.docs;
create policy docs_model_read on public.docs for select to authenticated
  using (
    (col in ('content', 'proposals') and model = public.my_model())
    or (col = 'models' and id = public.my_model())
    or col in ('tutorials', 'settings')
  );

-- Modelo: solo puede crear propuestas suyas ("Contenido Extra")
drop policy if exists docs_model_propose on public.docs;
create policy docs_model_propose on public.docs for insert to authenticated
  with check (col = 'proposals' and model = public.my_model());

-- 5. Botón "Hecho" de la modelo: solo cambia el estado de SU pieza
create or replace function public.mark_done(p_id text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.docs
     set data = data || jsonb_build_object('status', 'Recorded', 'recorded_date', to_char(now(), 'YYYY-MM-DD')),
         updated_at = now(),
         updated_by = auth.uid()
   where col = 'content'
     and id = p_id
     and model = public.my_model()
     and data->>'status' = 'Instructions Added';
  if not found then
    raise exception 'No puedes marcar esta pieza';
  end if;
end $$;
revoke all on function public.mark_done(text) from public;
grant execute on function public.mark_done(text) to authenticated;

-- 6. Al crear una cuenta se crea su perfil.
--    La PRIMERA cuenta que se registre será admin; las siguientes, modelo sin asignar.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (user_id, email, role)
  values (
    new.id,
    new.email,
    case when exists (select 1 from public.profiles where role = 'admin') then 'model' else 'admin' end
  );
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 7. Cambios en directo entre pantallas
do $$
begin
  alter publication supabase_realtime add table public.docs;
exception when duplicate_object then null;
end $$;
