# Supabase for sign-in, data and file storage

Teachers and students use different phones, so files and courses need a shared backend. We chose Supabase (free plan) because it gives sign-in, a Postgres database and file storage in one place at no cost. Firebase was rejected because file storage now needs a billing account, CloudKit because it needs the paid Apple Developer Program, and on-device storage because teachers and students could not actually share files.

## Consequences

- Files are capped at 50 MB each and 1 GB in total on the free plan.
- A free project pauses after a week without activity and must be resumed in the Supabase dashboard before a demo.
