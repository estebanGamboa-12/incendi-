-- ═══════════════════════════════════════════════════════════════════════════
--  Tabla para el mapa colaborativo de incendios.
--  Cómo usar: entra en tu proyecto de Supabase → SQL Editor → pega esto → RUN.
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
  status      text not null default 'active' check (status in ('active','resolved'))
);

create index if not exists idx_fire_reports_created on public.fire_reports (created_at desc);
create index if not exists idx_fire_reports_status  on public.fire_reports (status, created_at desc);

-- Seguridad (RLS): todos pueden leer y añadir avisos; nadie puede borrar los ajenos.
alter table public.fire_reports enable row level security;

drop policy if exists fire_reports_select on public.fire_reports;
create policy fire_reports_select on public.fire_reports for select using (true);

drop policy if exists fire_reports_insert on public.fire_reports;
create policy fire_reports_insert on public.fire_reports for insert with check (true);

drop policy if exists fire_reports_update_resolve on public.fire_reports;
create policy fire_reports_update_resolve on public.fire_reports for update
  using (true) with check (status in ('active','resolved'));

-- Tiempo real: que todos vean los avisos al instante.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='fire_reports'
  ) then
    execute 'alter publication supabase_realtime add table public.fire_reports';
  end if;
end $$;
