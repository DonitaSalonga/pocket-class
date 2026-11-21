create table public.courses (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  description text,
  join_code text not null unique default upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 6)),
  created_at timestamptz not null default now()
);
alter table public.courses enable row level security;
create policy "Teachers create own courses" on public.courses for insert to authenticated
  with check (teacher_id = auth.uid() and exists (select 1 from public.profiles where id = auth.uid() and role = 'teacher'));
create policy "Teachers read own courses" on public.courses for select to authenticated using (teacher_id = auth.uid());
create policy "Teachers update own courses" on public.courses for update to authenticated using (teacher_id = auth.uid()) with check (teacher_id = auth.uid());
