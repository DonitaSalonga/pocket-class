drop policy "Teachers and Students read roster rows" on public.course_memberships;
create policy "Students read own membership and Teachers read roster" on public.course_memberships for select to authenticated
  using (student_id = auth.uid() or public.is_course_teacher(course_id));

create policy "Teachers remove Students" on public.course_memberships for delete to authenticated
  using (public.is_course_teacher(course_id));

create or replace function public.course_roster(target_course_id uuid)
returns table(student_id uuid, name text, joined_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select m.student_id, p.name, m.joined_at
  from public.course_memberships m
  join public.profiles p on p.id = m.student_id
  where m.course_id = target_course_id and public.is_course_teacher(target_course_id)
  order by p.name;
$$;
revoke all on function public.course_roster(uuid) from public, anon;
grant execute on function public.course_roster(uuid) to authenticated;
