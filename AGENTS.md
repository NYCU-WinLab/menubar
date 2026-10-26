# AGENTS.md

## Rules

- **Build, test and run on a Mac.** This is the one WinLab repo that cannot use the sandbox: `swift test`, `scripts/dev-run.sh`.
- **The portal contract is the only source of API types.** Never edit `Sources/PortalKit/Generated.swift`; change `contract/actions.txt` and run `scripts/sync-contract.sh`. CI fails when the generated file is stale.
- **New portal action**: add its name to `contract/actions.txt`, sync, then call it with `client.run(Name.self, .init(...))`.
- **Native menu, not a popover.** The menu is an `NSMenu`; rows are `MenuRow` views sized by `MenuMetrics`, measured from the system Wi-Fi menu. Do not add custom backgrounds or Liquid Glass to rows (HIG: glass is for controls).
- **Builds go to `.build/dist`**, outside iCloud; iCloud's extended attributes break code signing.
- **Releases publish themselves.** Merging the Release Please pull request runs the `publish` job (`release-please.yml`): a macOS runner builds the tag, signs with the Developer ID, notarizes with the App Store Connect API key, makes the DMG, the Sparkle zip and appcast.xml, and publishes the release. The keys are secrets of the `release` environment, which only `main` can use. `scripts/release.sh vX.Y.Z` still works on a Mac with the keys in the keychain, as a fallback.
- **UI copy** is Traditional Chinese, without dashes or `·`.

## Verify

`swift run ContractGen check && swift test && scripts/bundle.sh`, then `scripts/dev-run.sh` and open the menu.
