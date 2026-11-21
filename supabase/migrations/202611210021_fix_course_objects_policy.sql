-- In the earlier policy `name` resolved to courses.name inside the subquery, so no upload could ever match a Course id.
-- Qualify it as storage.objects.name.
drop policy "Teachers manage own course objects" on storage.objects;
create policy "Teachers manage own course objects" on storage.objects for all to authenticated
    using (bucket_id = 'course-files' and exists (
        select 1 from public.courses c where c.id::text = (storage.foldername(objects.name))[1] and c.teacher_id = auth.uid()))
    with check (bucket_id = 'course-files' and exists (
        select 1 from public.courses c where c.id::text = (storage.foldername(objects.name))[1] and c.teacher_id = auth.uid()));
