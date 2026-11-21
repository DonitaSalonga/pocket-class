-- 0060 was already applied when review found that guard_course_columns (0005) pins join_code on UPDATE,
-- so regenerate_join_code returned a new code but stored nothing. Applied files are never edited, so fix it here.
-- The function sets a transaction-local setting holding the new code, and the guard lets exactly that value through.
-- Clients cannot call set_config over the API, so they cannot forge it.
create or replace function public.guard_course_columns()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.teacher_id := auth.uid();
    new.join_code := public.generate_join_code();
  else
    new.teacher_id := old.teacher_id;
    if new.join_code is distinct from nullif(current_setting('project2.new_join_code', true), '') then
      new.join_code := old.join_code;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.regenerate_join_code(course_id_input uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  new_code text;
begin
  if not public.is_course_teacher(course_id_input) then
    raise exception 'Only the owning Teacher can regenerate a Join Code' using errcode = '42501';
  end if;
  new_code := public.generate_join_code();
  perform set_config('project2.new_join_code', new_code, true);
  update public.courses set join_code = new_code where id = course_id_input;
  perform set_config('project2.new_join_code', '', true);
  return new_code;
end;
$$;
