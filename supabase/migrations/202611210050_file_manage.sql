-- A Teacher may rename a file (title) and delete it; nothing else about the row may change.
-- The existing "Teachers manage own course files" and "Teachers manage own course objects" policies already allow
-- UPDATE and DELETE for the owning Teacher only, so this migration only locks the other columns.
create function public.course_files_title_only() returns trigger language plpgsql as $$
begin
    if new.id is distinct from old.id
        or new.course_id is distinct from old.course_id
        or new.kind is distinct from old.kind
        or new.storage_path is distinct from old.storage_path
        or new.file_type is distinct from old.file_type
        or new.size is distinct from old.size
        or new.uploaded_at is distinct from old.uploaded_at then
        raise exception 'Only the title of a course file can be changed' using errcode = '42501';
    end if;
    return new;
end $$;

create trigger course_files_title_only before update on public.course_files
    for each row execute function public.course_files_title_only();
