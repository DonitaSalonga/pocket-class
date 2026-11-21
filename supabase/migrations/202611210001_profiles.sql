create type public.user_role as enum ('teacher', 'student');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  role public.user_role not null,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
create policy "Users can read their own profile" on public.profiles
  for select to authenticated using (auth.uid() = id);
create policy "Users can create their own profile" on public.profiles
  for insert to authenticated with check (auth.uid() = id);

create function public.create_profile_from_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, name, role)
  values (new.id, trim(new.raw_user_meta_data ->> 'name'), (new.raw_user_meta_data ->> 'role')::public.user_role);
  return new;
end;
$$;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.create_profile_from_auth_user();
