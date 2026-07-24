-- ═══════════════════════════════════════════════════════════════════════════
--  Tabla para el mapa colaborativo de incendios.
--  Cómo usar: entra en tu proyecto de Supabase → SQL Editor → pega esto → RUN.
--  (Puedes pegarlo entero aunque ya lo hubieras ejecutado antes: es idempotente.)
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.fire_reports (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  kind        text not null
                check (kind in ('fire','safe','shelter','help_needed',
                                'help_offered','road_blocked','water')),
  lat         double precision not null check (lat between -90 and 90),
  lng         double precision not null check (lng between -180 and 180),
  note        text check (char_length(note) <= 500),
  author      text check (char_length(author) <= 60),
  phone       text check (char_length(phone) <= 30),
  status      text not null default 'active' check (status in ('active','resolved'))
);

-- Para bases de datos creadas antes de añadir el teléfono (idempotente):
alter table public.fire_reports add column if not exists phone text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname='fire_reports_phone_len') then
    alter table public.fire_reports
      add constraint fire_reports_phone_len check (char_length(phone) <= 30);
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
  with check (author is not null and char_length(btrim(author)) > 0);

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
