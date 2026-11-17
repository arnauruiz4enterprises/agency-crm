-- Agency CRM · Archivos de las propuestas de las modelos ("Contenido Extra")
-- Ejecútalo una vez en Supabase → SQL Editor → New query → Run. Se puede repetir sin romper nada.
-- Requiere las funciones public.is_admin() y public.my_model() de schema.sql.

-- 1. Espacio privado para los archivos. Nadie puede verlos sin sesión: el CRM pide links temporales.
--    El límite por archivo (50 MB) es el máximo del plan Free de Supabase. Con el plan Pro se puede subir.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('proposals', 'proposals', false, 52428800, array['image/*', 'video/*'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- 2. Admin: puede ver, subir y borrar todo.
drop policy if exists proposals_files_admin on storage.objects;
create policy proposals_files_admin on storage.objects for all to authenticated
  using (bucket_id = 'proposals' and public.is_admin())
  with check (bucket_id = 'proposals' and public.is_admin());

-- 3. Modelo: solo dentro de su carpeta (la primera carpeta de la ruta es el id de su ficha).
drop policy if exists proposals_files_model_insert on storage.objects;
create policy proposals_files_model_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'proposals' and (storage.foldername(name))[1] = public.my_model());

drop policy if exists proposals_files_model_read on storage.objects;
create policy proposals_files_model_read on storage.objects for select to authenticated
  using (bucket_id = 'proposals' and (storage.foldername(name))[1] = public.my_model());

drop policy if exists proposals_files_model_delete on storage.objects;
create policy proposals_files_model_delete on storage.objects for delete to authenticated
  using (bucket_id = 'proposals' and (storage.foldername(name))[1] = public.my_model());
