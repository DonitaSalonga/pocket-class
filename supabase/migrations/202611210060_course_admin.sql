create function public.regenerate_join_code(course_id_input uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  new_code text;
begin
  if not public.is_course_teacher(course_id_input) then
    raise exception 'Only the owning Teacher can regenerate a Join Code' using errcode = '42501';
  end if;
  new_code := public.generate_join_code();
  update public.courses set join_code = new_code where id = course_id_input;
  return new_code;
end;
$$;
revoke execute on function public.regenerate_join_code(uuid) from public, anon;
grant execute on function public.regenerate_join_code(uuid) to authenticated;

create policy "Teachers delete own courses" on public.courses
  for delete to authenticated using (teacher_id = auth.uid());
