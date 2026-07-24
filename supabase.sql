-- ═══════════════════════════════════════════════════════════════════════════
--  Tabla para el mapa colaborativo de incendios.
--  Cómo usar: entra en tu proyecto de Supabase → SQL Editor → pega esto → RUN.
--  (Puedes pegarlo entero aunque ya lo hubieras ejecutado antes: es idempotente.)
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.fire_reports (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  kind        text not null
                check (kind in ('fire','evacuate','road_blocked','help_needed','elderly',
                                'animals','medical','car','shelter','supplies','help_offered',
                                'safe','water','custom')),
  lat         double precision not null check (lat between -90 and 90),
  lng         double precision not null check (lng between -180 and 180),
  note         text check (char_length(note) <= 500),
  author       text check (char_length(author) <= 60),
  phone        text check (char_length(phone) <= 30),
  custom_label text check (char_length(custom_label) <= 40),  -- etiqueta libre para kind='custom'
  capacity     int  check (capacity >= 0 and capacity <= 9999),-- nº de personas (plazas para dormir, etc.)
  confirms     int  not null default 0,                        -- nº de confirmaciones de vecinos
  owner_hash   text,                                           -- huella de la llave del autor (para borrar solo lo suyo)
  status      text not null default 'active' check (status in ('active','resolved'))
);

-- ── Columnas/constraints añadidas después (idempotente para bases existentes) ──
alter table public.fire_reports add column if not exists phone        text;
alter table public.fire_reports add column if not exists custom_label text;
alter table public.fire_reports add column if not exists capacity     int;
alter table public.fire_reports add column if not exists confirms     int not null default 0;
alter table public.fire_reports add column if not exists owner_hash   text;

-- Permitir todos los tipos actuales aunque la tabla ya existiera.
alter table public.fire_reports drop constraint if exists fire_reports_kind_check;
alter table public.fire_reports add constraint fire_reports_kind_check
  check (kind in ('fire','evacuate','road_blocked','help_needed','elderly','animals',
                  'medical','car','shelter','supplies','help_offered','safe','water','custom'));

do $$
begin
  if not exists (select 1 from pg_constraint where conname='fire_reports_phone_len') then
    alter table public.fire_reports
      add constraint fire_reports_phone_len check (char_length(phone) <= 30);
  end if;
  if not exists (select 1 from pg_constraint where conname='fire_reports_custom_len') then
    alter table public.fire_reports
      add constraint fire_reports_custom_len check (char_length(custom_label) <= 40);
  end if;
  if not exists (select 1 from pg_constraint where conname='fire_reports_capacity_rng') then
    alter table public.fire_reports
      add constraint fire_reports_capacity_rng check (capacity >= 0 and capacity <= 9999);
  end if;
end $$;

create index if not exists idx_fire_reports_created on public.fire_reports (created_at desc);
create index if not exists idx_fire_reports_status  on public.fire_reports (status, created_at desc);

-- ─────────────────────────────────────────────────────────────────────────────
--  Seguridad (RLS)
--  · Todos pueden LEER.
--  · Todos pueden AÑADIR un aviso.
--  · NADIE puede borrar ni reescribir el aviso de otro. La única modificación
--    permitida —marcar "resuelto"— se hace por una función controlada (abajo),
--    así que no hay policy de UPDATE directa: es imposible cambiar la nota,
--    el tipo o mover las coordenadas de un aviso ajeno.
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.fire_reports enable row level security;

drop policy if exists fire_reports_select on public.fire_reports;
create policy fire_reports_select on public.fire_reports for select using (true);

-- El nombre (author) es OBLIGATORIO: no se puede publicar un aviso anónimo,
-- ni siquiera saltándose el formulario.
drop policy if exists fire_reports_insert on public.fire_reports;
create policy fire_reports_insert on public.fire_reports for insert
  with check (
    author is not null and char_length(btrim(author)) > 0
    -- si es tipo personalizado, la etiqueta es obligatoria
    and (kind <> 'custom' or (custom_label is not null and char_length(btrim(custom_label)) > 0))
  );

-- Quitamos cualquier policy de UPDATE anterior (permitía reescribir avisos ajenos).
drop policy if exists fire_reports_update_resolve on public.fire_reports;

-- ─────────────────────────────────────────────────────────────────────────────
--  Marcar como resuelto: única modificación permitida.
--  Función SECURITY DEFINER que SOLO cambia status a 'resolved' y NADA MÁS.
--  Al no existir policy de UPDATE, esta es la puerta única y controlada.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.resolve_report(report_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.fire_reports
     set status = 'resolved'
   where id = report_id
     and status = 'active';
$$;

revoke all on function public.resolve_report(uuid) from public;
grant execute on function public.resolve_report(uuid) to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
--  Confirmar un aviso: suma 1 al contador de confirmaciones (validación vecinal).
--  Igual que resolve: función controlada, no permite tocar nada más.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.confirm_report(report_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.fire_reports
     set confirms = confirms + 1
   where id = report_id
     and status = 'active';
$$;

revoke all on function public.confirm_report(uuid) from public;
grant execute on function public.confirm_report(uuid) to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
--  Borrar SOLO lo tuyo, sin registro.
--  El navegador guarda una llave secreta (localStorage) y en el aviso se guarda
--  su huella SHA-256 (owner_hash). Para borrar hay que aportar la llave original:
--  la función la hashea y solo borra si coincide. Conocer la huella NO sirve para
--  borrar (haría falta la llave), así que es seguro aunque la huella sea pública.
-- ─────────────────────────────────────────────────────────────────────────────
create extension if not exists pgcrypto with schema extensions;

create or replace function public.delete_own_report(report_id uuid, token text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare n int;
begin
  delete from public.fire_reports
   where id = report_id
     and owner_hash is not null
     and owner_hash = encode(digest(token, 'sha256'), 'hex');
  get diagnostics n = row_count;
  return n > 0;
end $$;

revoke all on function public.delete_own_report(uuid, text) from public;
grant execute on function public.delete_own_report(uuid, text) to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
--  Tiempo real: que todos vean los avisos al instante.
-- ─────────────────────────────────────────────────────────────────────────────
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='fire_reports'
  ) then
    execute 'alter publication supabase_realtime add table public.fire_reports';
  end if;
end $$;
