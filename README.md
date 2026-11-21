# project-2

Native SwiftUI iPhone app. Requires Xcode 27 and xcodegen.

## Run

Copy `App/SupabaseConfig.example.swift` to `App/Sources/SupabaseConfig.swift`, then fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY` from `~/.config/project-2/supabase.env`. This generated file is ignored by git. Run `xcodegen generate`, then open `Project2.xcodeproj` in Xcode.

## Tests

Run unit tests: `xcodebuild test -project Project2.xcodeproj -scheme Project2 -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' CODE_SIGNING_ALLOWED=NO`

Run Supabase integration tests: `xcodebuild test -project Project2.xcodeproj -scheme Project2Integration -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' CODE_SIGNING_ALLOWED=NO`

Generate the ignored config from `~/.config/project-2/supabase.env`:

```sh
set -a
source ~/.config/project-2/supabase.env
set +a
cat > App/Sources/SupabaseConfig.swift <<EOF
import Foundation
enum SupabaseConfig {
    static let url = URL(string: "$SUPABASE_URL")!
    static let anonKey = "$SUPABASE_ANON_KEY"
}
EOF
xcodegen generate
```

### Integration test accounts

Supabase limits auth sign-ups and sign-ins per IP (about 30 per 5 minutes), so the integration tests share a fixed pool of accounts instead of creating users per test: `teacherA`, `teacherB`, `studentA`, `studentB` and `outsider` (`pool-<name>@example.com`). On first use `App/IntegrationTests/TestAccounts.swift` creates `~/.config/project-2/test-accounts.env` (mode 600, random passwords, never in the repo), signs each account up if it cannot sign in, and signs in once per account per run. One test still does a real fresh sign-up. Pool teachers keep their Courses between runs (there is no delete policy), so tests give Courses unique names and never assert an exact list. Never call `signOut` on a pool account: it revokes the sessions of every test using it. If the env file is lost, delete the `pool-*` users in the Supabase dashboard and rerun. Each run costs about 14 auth calls, so leave a few minutes between full runs and do not run them in parallel.

## Sessions and signing

The session lives in the Keychain, which needs a signed build. Build and run through Xcode (or `xcodebuild` without `CODE_SIGNING_ALLOWED=NO`) to stay signed in across launches. Integration tests use an in-memory session store instead, so they work unsigned.

Debug builds accept `-debugEmail <email> -debugPassword <password> [-debugTab profile]` launch arguments to sign in without typing (used for screenshots).

## Demo data

`scripts/seed-demo.sh` creates (and can safely re-run) a demo Teacher "Ms. Rivera", a demo Student "Ana Cruz", the Course "Biology 101" with 2 Presentations and 2 Exercises from the sample files in `App/DebugSamples`, and puts Ana on its Roster. It needs `jq` and `curl`, uses only the anon key and normal sign-in, and keeps the demo passwords in `~/.config/project-2/demo-accounts.env` (mode 600, created on first run, never in the repo). To demo, run the seed, then sign in with the emails and passwords from that file. Debug builds can skip typing with `-debugEmail <email> -debugPassword <password>`.

## Cleaning up test data

Integration tests and screenshot runs leave Courses on the pool Teachers' accounts. Delete them from the Course screen (Delete Course) or with the SQL cleanup described in `scripts/cleanup-test-data.sql`.
