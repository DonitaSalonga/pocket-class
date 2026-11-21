-- Course files are readable by the Teacher and current Roster Students.
create policy "Course members read course files" on public.course_files for select to authenticated
    using (public.is_course_member(course_id));

-- Storage policies remain teacher-write only; add member download access.
create policy "Course members read course objects" on storage.objects for select to authenticated
    using (bucket_id = 'course-files' and exists (
        select 1 from public.courses c where c.id::text = (storage.foldername(objects.name))[1]
            and public.is_course_member(c.id)));
