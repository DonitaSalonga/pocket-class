create table public.course_memberships (
  course_id uuid not null references public.courses(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (course_id, student_id)
);

alter table public.course_memberships enable row level security;

create policy "Teachers and Students read roster rows" on public.course_memberships for select to authenticated
  using (
    student_id = auth.uid()
    or exists (select 1 from public.courses where id = course_id and teacher_id = auth.uid())
  );
create policy "Students leave courses" on public.course_memberships for delete to authenticated
  using (student_id = auth.uid());

create policy "Roster Students read courses" on public.courses for select to authenticated
  using (exists (
    select 1 from public.course_memberships
    where course_id = courses.id and student_id = auth.uid()
  ));

create or replace function public.join_course(join_code_input text)
returns public.courses
language plpgsql
security definer
set search_path = ''
as $$
declare
  matched_course public.courses;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'student') then
    raise exception 'Only Students can join Courses.' using errcode = '42501';
  end if;

  select * into matched_course from public.courses
  where upper(join_code) = upper(trim(join_code_input));
  if not found then
    raise exception 'Join Code is incorrect or no longer valid.' using errcode = 'P0001';
  end if;

  insert into public.course_memberships(course_id, student_id)
  values (matched_course.id, auth.uid())
  on conflict (course_id, student_id) do nothing;
  return matched_course;
end;
$$;
revoke all on function public.join_course(text) from public;
grant execute on function public.join_course(text) to authenticated;
