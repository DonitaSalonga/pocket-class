-- Join Codes use 6 characters without ambiguous ones (0/O, 1/I/L), are generated here and never trusted from the client.
-- security definer so the collision check sees every Teacher's courses, not just the caller's rows.
create function public.generate_join_code()
returns text language plpgsql security definer set search_path = '' as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  candidate text;
begin
  loop
    candidate := '';
    for i in 1..6 loop
      candidate := candidate || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.courses where join_code = candidate);
  end loop;
  return candidate;
end;
$$;
revoke execute on function public.generate_join_code() from public, anon, authenticated;

create function public.guard_course_columns()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.teacher_id := auth.uid();
    new.join_code := public.generate_join_code();
  else
    new.teacher_id := old.teacher_id;
    new.join_code := old.join_code;
  end if;
  return new;
end;
$$;
revoke execute on function public.guard_course_columns() from public, anon, authenticated;

create trigger guard_course_columns before insert or update on public.courses
  for each row execute function public.guard_course_columns();

alter table public.courses alter column join_code drop default;
