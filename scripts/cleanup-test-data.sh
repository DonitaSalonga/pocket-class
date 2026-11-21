#!/usr/bin/env bash
# Deletes the Courses (and their stored files) that integration tests and screenshot runs left on the pool Teachers,
# then the stale auth users test+*@example.com and qa+*@example.com. Never touches pool-* or demo accounts.
# Needs jq, curl and a linked supabase CLI (see README). Prints counts first; pass --yes to delete.
set -euo pipefail

CONFIG_DIR="$HOME/.config/pocket-class"
set -a; source "$CONFIG_DIR/supabase.env"; set +a
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SQL="$ROOT/scripts/cleanup-test-data.sql"

echo "Before:"
supabase db query --linked --read-only -f "$SQL" 2>&1 | grep -v -E 'Warning|^Target' | jq -c '.rows[]'
[ "${1:-}" = "--yes" ] || { echo "Dry run. Pass --yes to delete."; exit 0; }

api() { local method=$1 path=$2 token=$3; shift 3
  curl -sS --fail-with-body -X "$method" "$SUPABASE_URL$path" -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $token" "$@"; }

for name in teacherA teacherB; do
  password=$(grep "^$name=" "$CONFIG_DIR/test-accounts.env" | cut -d= -f2-)
  email="pool-$(tr A-Z a-z <<<"$name")@example.com"
  token=$(curl -sS -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" -H "apikey: $SUPABASE_ANON_KEY" -H "Content-Type: application/json" -d "$(jq -n --arg e "$email" --arg p "$password" '{email:$e,password:$p}')" | jq -r '.access_token')
  # Storage objects first (the Course row delete does not remove them), then the Course with its Roster and file rows.
  for id in $(api GET "/rest/v1/courses?select=id" "$token" | jq -r '.[].id'); do
    folder=$(tr A-Z a-z <<<"$id")
    paths=$(api POST "/storage/v1/object/list/course-files" "$token" -H "Content-Type: application/json" -d "$(jq -n --arg p "$folder" '{prefix:$p,limit:1000}')" | jq -c --arg f "$folder" '[.[].name | "\($f)/\(.)"]')
    [ "$paths" = "[]" ] || api DELETE "/storage/v1/object/course-files" "$token" -H "Content-Type: application/json" -d "$(jq -n --argjson p "$paths" '{prefixes:$p}')" >/dev/null
    api DELETE "/rest/v1/courses?id=eq.$id" "$token" >/dev/null
  done
done

# Cascades to profiles, their Courses, Rosters and sessions.
supabase db query --linked --yes "delete from auth.users where email ~ '^(test|qa)\+[^@]*@example\.com\$'" >/dev/null
echo "After:"
supabase db query --linked --read-only -f "$SQL" 2>&1 | grep -v -E 'Warning|^Target' | jq -c '.rows[]'
