-- 02_mejoras.sql · Ejecutar DESPUÉS de 01_esquema.sql (re-ejecutable)

-- 1. Estado de cuenta + configuración (dominio de correo permitido)
alter table profiles add column if not exists estado text not null default 'activo'
  check(estado in('activo','suspendido'));
create table if not exists app_settings(id int primary key default 1 check(id=1), dominio_permitido text);
insert into app_settings(id) values(1) on conflict do nothing;
alter table app_settings enable row level security;          -- sin políticas: solo SQL Editor/funciones
revoke all on app_settings from anon, authenticated;

-- 2. Perfil automático al registrarse (funciona aunque se pida confirmar correo)
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path=public as $$
declare d text; m jsonb := coalesce(new.raw_user_meta_data,'{}'::jsonb);
begin
 select dominio_permitido into d from app_settings where id=1;
 if coalesce(d,'')<>'' and lower(split_part(new.email,'@',2))<>lower(d) then
  raise exception 'Solo se permiten correos @%', d; end if;
 insert into profiles(id,email,nombre,matricula,carrera,telefono)
 values(new.id,new.email,trim(m->>'nombre'),trim(m->>'matricula'),trim(m->>'carrera'),nullif(trim(m->>'telefono'),''));
 return new;
end $$;
revoke execute on function handle_new_user() from public, anon, authenticated;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

-- 3. Teléfono protegido: ya no se lee con select; se pide con obtener_contacto()
revoke select on posts from authenticated;
grant select(id,user_id,title,description,location,category,type,image_url,delivery_status,delivered_at,created_at,updated_at)
 on posts to authenticated;
create or replace function obtener_contacto(p_id bigint) returns text
language sql stable security definer set search_path=public as
$$ select tel from posts where id=p_id and auth.uid() is not null $$;
revoke execute on function obtener_contacto(bigint) from public, anon;
grant  execute on function obtener_contacto(bigint) to authenticated;

-- 4. Límite: máximo 5 publicaciones por 24 h (admins exentos)
create or replace function limitar_publicaciones() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if not is_admin() and (select count(*) from posts
    where user_id=new.user_id and created_at>now()-interval '24 hours')>=5 then
  raise exception 'Límite alcanzado: máximo 5 publicaciones cada 24 horas'; end if;
 return new;
end $$;
drop trigger if exists posts_limite on posts;
create trigger posts_limite before insert on posts for each row execute function limitar_publicaciones();

-- 5. Cuentas suspendidas no pueden publicar, comentar, preguntar ni reportar
create or replace function bloquear_suspendidos() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if exists(select 1 from profiles where id=auth.uid() and estado='suspendido') then
  raise exception 'Tu cuenta está suspendida'; end if;
 return new;
end $$;
do $$ declare t text; begin
 foreach t in array array['posts','comments','questions','answers','reports'] loop
  execute format('drop trigger if exists %I on %I', t||'_susp', t);
  execute format('create trigger %I before insert on %I for each row execute function bloquear_suspendidos()', t||'_susp', t);
 end loop; end $$;

-- 6. Bitácora automática: si un admin borra contenido ajeno, queda registrado
create or replace function log_moderacion() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is not null and old.user_id<>auth.uid() and is_admin() then
  insert into moderation_actions(admin_id,action,target_type,target_id,note)
  values(auth.uid(),'eliminar',tg_argv[0],old.id,
         left(coalesce(to_jsonb(old)->>'title',to_jsonb(old)->>'text',''),200));
 end if;
 return old;
end $$;
drop trigger if exists posts_log on posts;     drop trigger if exists questions_log on questions;
drop trigger if exists comments_log on comments; drop trigger if exists answers_log on answers;
create trigger posts_log     after delete on posts     for each row execute function log_moderacion('i');
create trigger questions_log after delete on questions for each row execute function log_moderacion('q');
create trigger comments_log  after delete on comments  for each row execute function log_moderacion('c');
create trigger answers_log   after delete on answers   for each row execute function log_moderacion('r');

-- 7. Suspender / reactivar usuarios (solo administradores)
create or replace function suspender_usuario(u uuid, s boolean) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not is_admin() then raise exception 'Solo administradores'; end if;
 update profiles set estado=case when s then 'suspendido' else 'activo' end where id=u;
 insert into moderation_actions(admin_id,action,note)
 values(auth.uid(),case when s then 'suspender' else 'reactivar' end,u::text);
end $$;
revoke execute on function suspender_usuario(uuid,boolean) from public, anon;
grant  execute on function suspender_usuario(uuid,boolean) to authenticated;

-- Opcional: solo correos institucionales (cambia el dominio por el real)
-- update app_settings set dominio_permitido='conalep.edu.mx' where id=1;
