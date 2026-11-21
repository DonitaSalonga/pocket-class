-- Presentations and Exercises of a Course. Until the Roster read policy lands (ticket #7), only the owning Teacher can touch rows or objects.
create table public.course_files (
    id uuid primary key default gen_random_uuid(),
    course_id uuid not null references public.courses(id) on delete cascade,
    kind text not null check (kind in ('presentation', 'exercise')),
    title text not null check (length(trim(title)) > 0),
    storage_path text not null unique,
    file_type text not null,
    size bigint not null check (size > 0 and size <= 52428800),
    uploaded_at timestamptz not null default now(),
    -- Same type lists as the app: Presentations .pptx .ppt .key .pdf; Exercises .pdf .docx .pptx.
    check ((kind = 'presentation' and file_type in ('pptx', 'ppt', 'key', 'pdf'))
        or (kind = 'exercise' and file_type in ('pdf', 'docx', 'pptx'))),
    -- Objects live under the Course id, which the storage policies key on.
    check (storage_path like course_id::text || '/%')
);
create index course_files_course_id_uploaded_at on public.course_files (course_id, uploaded_at desc);

alter table public.course_files enable row level security;
create policy "Teachers manage own course files" on public.course_files for all to authenticated
    using (public.is_course_teacher(course_id))
    with check (public.is_course_teacher(course_id));

-- Private bucket: 50 MB and office/PDF types are enforced by storage itself, not only by the app.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('course-files', 'course-files', false, 52428800, array[
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/vnd.ms-powerpoint',
    'application/x-iwork-keynote-sffkey',
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
]);

-- The first path segment is the Course id. Compared as text: other buckets hold paths that are not UUIDs.
create policy "Teachers manage own course objects" on storage.objects for all to authenticated
    using (bucket_id = 'course-files' and exists (
        select 1 from public.courses c where c.id::text = (storage.foldername(name))[1] and c.teacher_id = auth.uid()))
    with check (bucket_id = 'course-files' and exists (
        select 1 from public.courses c where c.id::text = (storage.foldername(name))[1] and c.teacher_id = auth.uid()));
