-- CONALEP Objetos Perdidos · versión endurecida
-- Ejecutar COMPLETO en Supabase > SQL Editor > New query
-- Es re-ejecutable (idempotente) en tablas, políticas y funciones.

-- =====================================================================
-- 1. TABLAS
-- =====================================================================
create table if not exists profiles(
 id uuid primary key references auth.users on delete cascade,
 email text not null,
 nombre text not null check(length(nombre) between 3 and 80),
 matricula text not null unique
   check(length(matricula) between 4 and 20 and matricula ~ '^[A-Za-z0-9-]+$'),
 carrera text not null check(length(carrera) between 2 and 100),
 telefono text check(telefono ~ '^[0-9+() -]{7,20}$'),
 foto text,
 rol text not null default 'usuario' check(rol in('usuario','administrador')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now());

create table if not exists posts(
 id bigint generated always as identity primary key,
 user_id uuid not null default auth.uid() references profiles on delete cascade,
 title text not null check(length(title) between 2 and 100),
 description text check(length(description)<=1000),
 location text check(length(location)<=120),
 category text not null check(length(category) between 2 and 50),
 type text not null check(type in('Lo perdí','Lo encontré')),
 tel text check(tel ~ '^[0-9+() -]{7,20}$'),
 image_url text,
 delivery_status text not null default 'pendiente'
   check(delivery_status in('pendiente','en_proceso','entregado')),
 delivered_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now());

create table if not exists comments(
 id bigint generated always as identity primary key,
 post_id bigint not null references posts on delete cascade,
 user_id uuid not null default auth.uid() references profiles on delete cascade,
 text text not null check(length(text) between 1 and 1000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now());

create table if not exists questions(
 id bigint generated always as identity primary key,
 user_id uuid not null default auth.uid() references profiles on delete cascade,
 text text not null check(length(text) between 1 and 1000),
 image_url text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now());

create table if not exists answers(
 id bigint generated always as identity primary key,
 question_id bigint not null references questions on delete cascade,
 user_id uuid not null default auth.uid() references profiles on delete cascade,
 text text not null check(length(text) between 1 and 1000),
 image_url text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now());

-- i=publicación, q=pregunta, c=comentario, r=respuesta
create table if not exists reactions(
 id bigint generated always as identity primary key,
 user_id uuid not null default auth.uid() references profiles on delete cascade,
 target_type text not null check(target_type in('i','q','c','r')),
 target_id bigint not null,
 type text not null check(type in('thumb','laugh','heart')),
 created_at timestamptz not null default now(),
 unique(user_id,target_type,target_id));   -- máximo 1 reacción por usuario y contenido

create table if not exists reports(
 id bigint generated always as identity primary key,
 reporter_id uuid not null default auth.uid() references profiles on delete cascade,
 target_type text not null check(target_type in('i','q','c','r')),
 target_id bigint not null,
 reason text not null check(length(reason) between 3 and 500),
 status text not null default 'abierto' check(status in('abierto','revisado','cerrado')),
 created_at timestamptz not null default now(),
 unique(reporter_id,target_type,target_id));   -- evita spam de reportes

create table if not exists moderation_actions(
 id bigint generated always as identity primary key,
 admin_id uuid not null default auth.uid() references profiles,
 action text not null check(length(action) between 2 and 100),
 target_type text check(target_type in('i','q','c','r')),
 target_id bigint,
 note text check(length(note)<=500),
 created_at timestamptz not null default now());

-- Índices (incluye claves foráneas para acelerar joins y borrados en cascada)
create index if not exists posts_created_idx    on posts(created_at desc);
create index if not exists posts_user_idx       on posts(user_id);
create index if not exists comments_post_idx    on comments(post_id);
create index if not exists comments_user_idx    on comments(user_id);
create index if not exists questions_user_idx   on questions(user_id);
create index if not exists answers_question_idx on answers(question_id);
create index if not exists answers_user_idx     on answers(user_id);
create index if not exists reactions_target_idx on reactions(target_type,target_id);
create index if not exists reports_reporter_idx on reports(reporter_id);
create index if not exists reports_target_idx   on reports(target_type,target_id);

-- Vista pública: NO expone correo, teléfono ni rol.
-- Corre con permisos del dueño a propósito (security_invoker=false) para
-- mostrar nombre/foto de cualquier autor aunque profiles solo deje ver el propio.
create or replace view public_profiles with (security_invoker=false) as
 select id,nombre,carrera,foto,created_at from profiles;

-- =====================================================================
-- 2. FUNCIONES Y TRIGGERS
-- =====================================================================
create or replace function is_admin() returns boolean
language sql stable security definer set search_path=public as
$$ select exists(select 1 from profiles where id=(select auth.uid()) and rol='administrador') $$;
revoke execute on function is_admin() from public, anon;
grant  execute on function is_admin() to authenticated;

-- updated_at automático (genérico)
create or replace function set_updated_at() returns trigger
language plpgsql set search_path=public as $$
begin new.updated_at=now(); return new; end $$;

-- posts: fecha de entrega + updated_at
create or replace function posts_bu() returns trigger
language plpgsql set search_path=public as $$
begin
 if new.delivery_status='entregado' and old.delivery_status is distinct from 'entregado' then
  new.delivered_at=now();
 elsif new.delivery_status<>'entregado' then
  new.delivered_at=null;
 end if;
 new.updated_at=now();
 return new;
end $$;

drop trigger if exists posts_bu on posts;
create trigger posts_bu before update on posts for each row execute function posts_bu();

do $$ declare t text; begin
 foreach t in array array['profiles','comments','questions','answers'] loop
  execute format('drop trigger if exists %I on %I', t||'_upd', t);
  execute format('create trigger %I before update on %I for each row execute function set_updated_at()', t||'_upd', t);
 end loop; end $$;

-- Reacción: pulsar la misma la quita, otra distinta la reemplaza.
-- SECURITY DEFINER + validaciones: es la ÚNICA vía para crear reacciones
-- (se revoca insert/update directo más abajo).
create or replace function toggle_reaction(t text,tid bigint,k text) returns void
language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); n int; ok boolean;
begin
 if uid is null then raise exception 'No autenticado' using errcode='28000'; end if;
 if k not in('thumb','laugh','heart') then raise exception 'Reacción inválida'; end if;
 ok := case t
  when 'i' then exists(select 1 from posts     where id=tid)
  when 'q' then exists(select 1 from questions where id=tid)
  when 'c' then exists(select 1 from comments  where id=tid)
  when 'r' then exists(select 1 from answers   where id=tid)
  else false end;
 if not ok then raise exception 'El contenido no existe'; end if;

 delete from reactions where user_id=uid and target_type=t and target_id=tid and type=k;
 get diagnostics n=row_count;
 if n=0 then
  insert into reactions(user_id,target_type,target_id,type) values(uid,t,tid,k)
  on conflict(user_id,target_type,target_id) do update set type=excluded.type;
 end if;
end $$;
revoke execute on function toggle_reaction(text,bigint,text) from public, anon;
grant  execute on function toggle_reaction(text,bigint,text) to authenticated;

-- Limpieza de reacciones huérfanas (la relación es polimórfica, sin FK)
create or replace function cleanup_reactions() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 delete from reactions where target_type=tg_argv[0] and target_id=old.id;
 return old;
end $$;

drop trigger if exists posts_clean     on posts;
drop trigger if exists questions_clean on questions;
drop trigger if exists comments_clean  on comments;
drop trigger if exists answers_clean   on answers;
create trigger posts_clean     after delete on posts     for each row execute function cleanup_reactions('i');
create trigger questions_clean after delete on questions for each row execute function cleanup_reactions('q');
create trigger comments_clean  after delete on comments  for each row execute function cleanup_reactions('c');
create trigger answers_clean   after delete on answers   for each row execute function cleanup_reactions('r');

-- =====================================================================
-- 3. SEGURIDAD A NIVEL DE FILA (RLS)
--    (select auth.uid()) se evalúa una vez por consulta, no por fila.
-- =====================================================================
alter table profiles          enable row level security;
alter table reactions         enable row level security;
alter table reports           enable row level security;
alter table moderation_actions enable row level security;

do $$ declare t text; begin
 foreach t in array array['posts','comments','questions','answers'] loop
  execute format('alter table %I enable row level security',t);
  execute format('drop policy if exists "ver" on %I',t);
  execute format('drop policy if exists "crear" on %I',t);
  execute format('drop policy if exists "editar" on %I',t);
  execute format('drop policy if exists "borrar" on %I',t);
  execute format('create policy "ver" on %I for select to authenticated using(true)',t);
  execute format('create policy "crear" on %I for insert to authenticated with check(user_id=(select auth.uid()))',t);
  execute format('create policy "editar" on %I for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()))',t);
  execute format('create policy "borrar" on %I for delete to authenticated using(user_id=(select auth.uid()) or is_admin())',t);
 end loop; end $$;

drop policy if exists "ver propio"   on profiles;
drop policy if exists "crear propio" on profiles;
drop policy if exists "editar propio" on profiles;
create policy "ver propio" on profiles for select to authenticated
 using(id=(select auth.uid()) or is_admin());
create policy "crear propio" on profiles for insert to authenticated
 with check(id=(select auth.uid()) and email=(select auth.jwt()->>'email'));
create policy "editar propio" on profiles for update to authenticated
 using(id=(select auth.uid())) with check(id=(select auth.uid()));

-- Reacciones: solo lectura y borrado propio; crear/cambiar va por toggle_reaction()
drop policy if exists "ver"    on reactions;
drop policy if exists "crear"  on reactions;
drop policy if exists "editar" on reactions;
drop policy if exists "borrar" on reactions;
create policy "ver"    on reactions for select to authenticated using(true);
create policy "borrar" on reactions for delete to authenticated using(user_id=(select auth.uid()));

drop policy if exists "reportar"      on reports;
drop policy if exists "ver reportes"  on reports;
drop policy if exists "gestionar"     on reports;
create policy "reportar" on reports for insert to authenticated
 with check(reporter_id=(select auth.uid()));
create policy "ver reportes" on reports for select to authenticated
 using(reporter_id=(select auth.uid()) or is_admin());
create policy "gestionar" on reports for update to authenticated
 using(is_admin()) with check(is_admin());

drop policy if exists "admin ve"       on moderation_actions;
drop policy if exists "admin registra" on moderation_actions;
create policy "admin ve" on moderation_actions for select to authenticated using(is_admin());
create policy "admin registra" on moderation_actions for insert to authenticated
 with check(is_admin() and admin_id=(select auth.uid()));

-- =====================================================================
-- 4. PERMISOS POR COLUMNA (mínimo privilegio)
-- =====================================================================
-- anon: sin acceso a nada, ahora y en tablas futuras
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from anon;
alter default privileges in schema public revoke all on tables    from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke execute on functions from anon;

-- authenticated: se quita todo lo que no se usa y se concede columna por columna
revoke truncate,references,trigger on all tables in schema public from authenticated;
revoke insert,update on profiles,posts,comments,questions,answers,
                        reactions,reports,moderation_actions from authenticated;
revoke delete on reports,moderation_actions from authenticated;

grant insert(id,email,nombre,matricula,carrera,telefono,foto) on profiles to authenticated;
grant update(nombre,carrera,telefono,foto)                    on profiles to authenticated;

grant insert(title,description,location,category,type,tel,image_url) on posts to authenticated;
grant update(title,description,location,category,type,tel,image_url,delivery_status) on posts to authenticated;

grant insert(post_id,text)            on comments  to authenticated;
grant insert(question_id,text,image_url) on answers to authenticated;
grant insert(text,image_url)          on questions to authenticated;
grant update(text)                    on comments,answers to authenticated;
grant update(text,image_url)          on questions to authenticated;

-- reactions: sin insert/update directo (solo toggle_reaction)
grant insert(target_type,target_id,reason) on reports to authenticated;
grant update(status)                       on reports to authenticated;   -- RLS: solo admin
grant insert(action,target_type,target_id,note) on moderation_actions to authenticated; -- RLS: solo admin

grant select on public_profiles to authenticated;

-- =====================================================================
-- 5. IMÁGENES (Storage)
-- =====================================================================
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('img','img',true,3145728,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set
 public=excluded.public,
 file_size_limit=excluded.file_size_limit,
 allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "img subir propio"  on storage.objects;
drop policy if exists "img borrar propio" on storage.objects;
create policy "img subir propio" on storage.objects for insert to authenticated
 with check(bucket_id='img' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "img borrar propio" on storage.objects for delete to authenticated
 using(bucket_id='img' and (storage.foldername(name))[1]=(select auth.uid())::text);

-- =====================================================================
-- 6. TIEMPO REAL (sin error si ya estaban agregadas)
-- =====================================================================
do $$ declare t text; begin
 foreach t in array array['posts','comments','questions','answers','reactions'] loop
  if not exists(select 1 from pg_publication_tables
                where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
   execute format('alter publication supabase_realtime add table %I',t);
  end if;
 end loop; end $$;

-- Para hacerte administrador (solo desde el SQL Editor, con tu correo):
-- update profiles set rol='administrador' where email='tucorreo@ejemplo.com';
