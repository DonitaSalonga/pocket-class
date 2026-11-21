-- The courses and course_memberships select policies queried each other, so every read of courses failed with
-- "infinite recursion detected in policy". These security definer helpers read the tables without re-entering RLS.
create function public.is_course_member(target_course_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.course_memberships
    where course_id = target_course_id and student_id = auth.uid()
  );
$$;
create function public.is_course_teacher(target_course_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.courses
    where id = target_course_id and teacher_id = auth.uid()
  );
$$;
revoke all on function public.is_course_member(uuid) from public, anon;
revoke all on function public.is_course_teacher(uuid) from public, anon;
grant execute on function public.is_course_member(uuid) to authenticated;
grant execute on function public.is_course_teacher(uuid) to authenticated;

drop policy "Roster Students read courses" on public.courses;
create policy "Roster Students read courses" on public.courses for select to authenticated
  using (public.is_course_member(id));

drop policy "Teachers and Students read roster rows" on public.course_memberships;
create policy "Teachers and Students read roster rows" on public.course_memberships for select to authenticated
  using (student_id = auth.uid() or public.is_course_teacher(course_id));
