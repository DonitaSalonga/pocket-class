create function public.prevent_profile_role_change()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.role is distinct from old.role then
    raise exception 'Profile role cannot be changed';
  end if;
  return new;
end;
$$;
create trigger profile_role_is_immutable
  before update on public.profiles for each row execute function public.prevent_profile_role_change();
