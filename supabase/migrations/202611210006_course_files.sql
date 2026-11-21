create table public.course_files (
    id uuid primary key default gen_random_uuid(),
    course_id uuid not null references public.courses(id) on delete cascade,
    kind text not null check (kind in ('presentation', 'exercise')),
    title text not null,
    storage_path text not null unique,
    file_type text not null,
    size bigint not null check (size > 0 and size <= 52428800),
    uploaded_at timestamptz not null default now()
);

alter table public.course_files enable row level security;
create policy "Teachers manage own course files" on public.course_files
    for all using (exists (select 1 from public.courses c where c.id = course_id and c.teacher_id = auth.uid()))
    with check (exists (select 1 from public.courses c where c.id = course_id and c.teacher_id = auth.uid()));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('course-files', 'course-files', false, 52428800,
    array['application/vnd.openxmlformats-officedocument.presentationml.presentation', 'application/vnd.ms-powerpoint', 'application/x-iwork-keynote-sffkey', 'application/pdf', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document']);

create policy "Teachers manage own course objects" on storage.objects
    for all using (bucket_id = 'course-files' and exists (
        select 1 from public.courses c where c.id::text = (storage.foldername(name))[1] and c.teacher_id = auth.uid()
    )) with check (bucket_id = 'course-files' and exists (
        select 1 from public.courses c where c.id::text = (storage.foldername(name))[1] and c.teacher_id = auth.uid()
    ));
