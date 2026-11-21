-- Counts of leftover test data. Read-only; scripts/cleanup-test-data.sh runs it before and after deleting.
select
  (select count(*) from courses c join auth.users u on u.id = c.teacher_id where u.email like 'pool-teacher%') as pool_courses,
  (select count(*) from storage.objects o join courses c on c.id::text = split_part(o.name, '/', 1) join auth.users u on u.id = c.teacher_id where o.bucket_id = 'course-files' and u.email like 'pool-teacher%') as pool_objects,
  (select count(*) from auth.users where email ~ '^(test|qa)\+[^@]*@example\.com$') as stale_users,
  (select count(*) from courses c join auth.users u on u.id = c.teacher_id where u.email ~ '^(test|qa)\+[^@]*@example\.com$') as stale_user_courses;
