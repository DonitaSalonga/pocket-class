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

## Sessions and signing

The session lives in the Keychain, which needs a signed build. Build and run through Xcode (or `xcodebuild` without `CODE_SIGNING_ALLOWED=NO`) to stay signed in across launches. Integration tests use an in-memory session store instead, so they work unsigned.

Debug builds accept `-debugEmail <email> -debugPassword <password> [-debugTab profile]` launch arguments to sign in without typing (used for screenshots).
