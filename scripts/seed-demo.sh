#!/usr/bin/env bash
# Seeds the demo data: Teacher "Ms. Rivera", Student "Ana Cruz", Course "Biology 101"
# with 2 Presentations and 2 Exercises, and Ana on its Roster. Safe to run again.
# Uses only the anon key and normal sign-in. Passwords live in ~/.config/project-2/demo-accounts.env.
set -euo pipefail

CONFIG_DIR="$HOME/.config/project-2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SAMPLES="$ROOT/App/DebugSamples"
COURSE_NAME="Biology 101"

set -a; source "$CONFIG_DIR/supabase.env"; set +a

if [ ! -f "$CONFIG_DIR/demo-accounts.env" ]; then
  umask 077
  cat > "$CONFIG_DIR/demo-accounts.env" <<ENV
DEMO_TEACHER_EMAIL=demo-rivera@example.com
DEMO_TEACHER_PASSWORD=$(openssl rand -hex 12)
DEMO_STUDENT_EMAIL=demo-ana@example.com
DEMO_STUDENT_PASSWORD=$(openssl rand -hex 12)
ENV
fi
chmod 600 "$CONFIG_DIR/demo-accounts.env"
set -a; source "$CONFIG_DIR/demo-accounts.env"; set +a

api() { # method path token [curl args...]; body from the remaining args
  local method=$1 path=$2 token=$3; shift 3
  curl -sS --fail-with-body -X "$method" "$SUPABASE_URL$path" -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $token" "$@"
}

# Prints an access token; signs the account up first when sign-in fails.
session() { # email password name role
  local email=$1 password=$2 name=$3 role=$4 body token
  body=$(jq -n --arg e "$email" --arg p "$password" '{email:$e,password:$p}')
  token=$(curl -sS -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" -H "apikey: $SUPABASE_ANON_KEY" -H "Content-Type: application/json" -d "$body" | jq -r '.access_token // empty')
  if [ -z "$token" ]; then
    body=$(jq -n --arg e "$email" --arg p "$password" --arg n "$name" --arg r "$role" '{email:$e,password:$p,data:{name:$n,role:$r}}')
    token=$(curl -sS -X POST "$SUPABASE_URL/auth/v1/signup" -H "apikey: $SUPABASE_ANON_KEY" -H "Content-Type: application/json" -d "$body" | jq -r '.access_token // empty')
  fi
  [ -n "$token" ] || { echo "Could not sign in or sign up $email" >&2; exit 1; }
  echo "$token"
}

teacher=$(session "$DEMO_TEACHER_EMAIL" "$DEMO_TEACHER_PASSWORD" "Ms. Rivera" teacher)
student=$(session "$DEMO_STUDENT_EMAIL" "$DEMO_STUDENT_PASSWORD" "Ana Cruz" student)

course=$(api GET "/rest/v1/courses?name=eq.$(jq -rn --arg n "$COURSE_NAME" '$n|@uri')&select=id,join_code&limit=1" "$teacher")
if [ "$(jq length <<<"$course")" = 0 ]; then
  course=$(api POST "/rest/v1/courses" "$teacher" -H "Content-Type: application/json" -H "Prefer: return=representation" -d "$(jq -n --arg n "$COURSE_NAME" '{name:$n}')")
  echo "Created Course $COURSE_NAME"
fi
course_id=$(jq -r '.[0].id' <<<"$course"); join_code=$(jq -r '.[0].join_code' <<<"$course")

mime() { case $1 in pptx) echo application/vnd.openxmlformats-officedocument.presentationml.presentation;; *) echo application/pdf;; esac; }
have=$(api GET "/rest/v1/course_files?course_id=eq.$course_id&select=title" "$teacher")
for entry in "presentation|Week 1: Cells|sample.pptx" "presentation|Cell diagrams|sample.pdf" "exercise|Worksheet 1|sample.pdf" "exercise|Lab report template|sample.pptx"; do
  IFS='|' read -r kind title file <<<"$entry"
  jq -e --arg t "$title" 'any(.[]; .title == $t)' <<<"$have" >/dev/null && continue
  ext=${file##*.}; path="$course_id/$(uuidgen | tr A-Z a-z).$ext"
  api POST "/storage/v1/object/course-files/$path" "$teacher" -H "Content-Type: $(mime "$ext")" --data-binary "@$SAMPLES/$file" >/dev/null
  api POST "/rest/v1/course_files" "$teacher" -H "Content-Type: application/json" -d "$(jq -n --arg c "$course_id" --arg k "$kind" --arg t "$title" --arg p "$path" --arg x "$ext" --argjson s "$(wc -c <"$SAMPLES/$file" | tr -d ' ')" '{course_id:$c,kind:$k,title:$t,storage_path:$p,file_type:$x,size:$s}')" >/dev/null
  echo "Uploaded $title"
done

api POST "/rest/v1/rpc/join_course" "$student" -H "Content-Type: application/json" -d "$(jq -n --arg c "$join_code" '{join_code_input:$c}')" >/dev/null
echo "Demo ready: $COURSE_NAME (Join Code $join_code). Sign-in details are in $CONFIG_DIR/demo-accounts.env"
