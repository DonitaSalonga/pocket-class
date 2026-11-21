# project-2

Native SwiftUI iPhone app. Requires Xcode 27 and xcodegen.

## Run

Copy `App/SupabaseConfig.example.swift` to `App/Sources/SupabaseConfig.swift`, then fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY` from `~/.config/project-2/supabase.env`. This generated file is ignored by git. Run `xcodegen generate`, then open `Project2.xcodeproj` in Xcode.

## Tests

Run unit tests: `xcodebuild test -project Project2.xcodeproj -scheme Project2 -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:Project2Tests/AuthBackendTests`

Run Supabase integration tests: `xcodebuild test -project Project2.xcodeproj -scheme Project2 -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:Project2Tests/SupabaseIntegrationTests`
