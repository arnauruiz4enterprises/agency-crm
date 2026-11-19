-- Agency CRM · Archivos que la modelo sube a cada pieza de contenido
-- Ejecútalo una vez en Supabase → SQL Editor → New query → Run. Se puede repetir sin romper nada.
-- Requiere storage.sql (espacio de archivos) y las funciones de schema.sql.

-- 1. La modelo guarda la lista de archivos de SU pieza (mientras está en "Instructions Added" o "Not Approved").
--    Los archivos que la agencia marcó para repetir conservan la marca: la modelo solo puede quitarlos, no desmarcarlos.
--    Cada archivo tiene que estar dentro de la carpeta <su modelo>/<id de la pieza>/.
create or replace function public.set_content_files(p_id text, p_files jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f jsonb; pre text; old jsonb; o jsonb; res jsonb := '[]'::jsonb;
begin
  pre := public.my_model() || '/' || p_id || '/';
  if public.my_model() is null then raise exception 'Solo para modelos'; end if;
  if p_files is null or jsonb_typeof(p_files) <> 'array' or jsonb_array_length(p_files) > 60 then
    raise exception 'Lista de archivos no válida';
  end if;
  select data->'raw_files' into old from public.docs
   where col = 'content' and id = p_id and model = public.my_model() and data->>'status' in ('Instructions Added', 'Not Approved')
   for update;
  if not found then raise exception 'No puedes cambiar esta pieza'; end if;
  if old is null or jsonb_typeof(old) <> 'array' then old := '[]'::jsonb; end if;
  for f in select * from jsonb_array_elements(p_files) loop
    if jsonb_typeof(f) <> 'object' or coalesce(f->>'path', '') = '' or left(f->>'path', length(pre)) <> pre then
      raise exception 'Archivo no válido';
    end if;
    f := f - 'redo' - 'redo_note';
    select e into o from jsonb_array_elements(old) e where e->>'path' = f->>'path' limit 1;
    if o is not null and coalesce((o->>'redo')::boolean, false) then
      f := f || jsonb_build_object('redo', true, 'redo_note', o->'redo_note');
    end if;
    o := null;
    res := res || jsonb_build_array(f);
  end loop;
  update public.docs
     set data = data || jsonb_build_object('raw_files', res), updated_at = now(), updated_by = auth.uid()
   where col = 'content' and id = p_id;
  return res;
end $$;
revoke all on function public.set_content_files(text, jsonb) from public;
grant execute on function public.set_content_files(text, jsonb) to authenticated;

-- 2. Botón "Hecho": solo deja marcarla si ha subido exactamente los archivos que pide la pieza.
--    files_needed lo calcula el CRM (archivos por repetición × repeticiones) cada vez que se guarda la pieza.
create or replace function public.mark_done(p_id text) returns void
language plpgsql security definer set search_path = public as $$
declare d jsonb; need int; have int; redo int;
begin
  select data into d from public.docs
   where col = 'content' and id = p_id and model = public.my_model() and data->>'status' in ('Instructions Added', 'Not Approved')
   for update;
  if d is null then raise exception 'No puedes marcar esta pieza'; end if;
  have := case when jsonb_typeof(d->'raw_files') = 'array' then jsonb_array_length(d->'raw_files') else 0 end;
  need := greatest(1, coalesce(nullif(d->>'files_needed', '')::numeric, 1)::int);
  if have < need then raise exception 'Te faltan % archivo(s): has subido % de %', need - have, have, need; end if;
  if have > need then raise exception 'Te sobran % archivo(s): has subido % y esta pieza pide %', have - need, have, need; end if;
  select count(*) into redo from jsonb_array_elements(case when jsonb_typeof(d->'raw_files') = 'array' then d->'raw_files' else '[]'::jsonb end) e
   where coalesce((e->>'redo')::boolean, false);
  if redo > 0 then raise exception 'Tienes % archivo(s) marcados para repetir: quítalos y sube los nuevos', redo; end if;
  update public.docs
     set data = data || jsonb_build_object('status', 'Recorded', 'recorded_date', to_char(now(), 'YYYY-MM-DD'))
                     || case when d->>'status' = 'Not Approved' then jsonb_build_object('corrected_date', to_char(now(), 'YYYY-MM-DD')) else '{}'::jsonb end,
         updated_at = now(), updated_by = auth.uid()
   where col = 'content' and id = p_id;
end $$;
revoke all on function public.mark_done(text) from public;
grant execute on function public.mark_done(text) to authenticated;
