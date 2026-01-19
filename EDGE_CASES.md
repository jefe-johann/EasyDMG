# EasyDMG Edge Cases & Potential Issues

This document catalogs potential issues and edge cases that could affect automatic DMG installation. Each issue includes a likelihood rating (1-10) based on how commonly it might be encountered.

## File Attributes & Security

### 1. App Translocation (Gatekeeper Path Randomization) - Rating: 7/10

macOS "translocates" quarantined apps to randomized read-only locations (`/private/var/folders/...`) for security. Some apps detect they're translocated and show "Move to Applications" prompts. Since we're removing the quarantine flag, translocation shouldn't happen, but some apps might still check their path and get confused if they expect to be translocated on first launch.

**Impact**: Apps might show unexpected "Move to Applications" prompts or warnings about running from the wrong location.

### 2. Extended Attribute Preservation Beyond Quarantine - Rating: 5/10

We're removing `com.apple.quarantine`, but there are other extended attributes like:
- `com.apple.metadata.kMDItemWhereFroms` - Download URL history
- `com.apple.FinderInfo` - Finder display settings
- `com.apple.TextEncoding` - Text encoding info

Some apps might rely on these for analytics or first-run detection.

**Impact**: Apps might lose download provenance information used for analytics or debugging.

### 3. Code Signature Validation Timing - Rating: 4/10

Some apps validate their own code signature on launch. If we copy during a moment when the app is being updated or has partial writes, signature validation could fail. FileManager.copyItem is atomic, but if the source DMG has corruption, we'd copy the corrupted version.

**Impact**: Apps might refuse to launch due to signature validation failures.

## App Bundle Complexity

### 4. Symlinks to Shared Frameworks - Rating: 8/10

Many apps have symlinked frameworks (e.g., `Versions/Current -> Versions/A`). FileManager.copyItem should preserve these, but if it doesn't, apps would break. Worth testing that we're preserving symlinks correctly.

**Impact**: Apps would crash on launch with missing framework errors.

### 5. XPC Services and Helper Tools - Rating: 6/10

Apps with XPC services (in `Contents/XPCServices/`) or privileged helpers might have special registration requirements. They might expect to register on first launch with quarantine present, but we're skipping that.

**Impact**: Background services or helper tools might not work correctly until app is relaunched.

### 6. Embedded Provisioning Profiles - Rating: 4/10

Developer-signed apps have `embedded.provisionprofile` files. Some apps check if their profile is still valid on launch. If copying doesn't preserve timestamps correctly, validation might fail.

**Impact**: Developer builds might refuse to launch or show expiration warnings.

## DMG Content Variations

### 7. PKG Installers Masquerading as Apps - Rating: 6/10

Some DMGs contain `.app` files that are actually just installer wrappers. They expect to run once, install the real app elsewhere, then quit. We'd copy the installer wrapper to /Applications, not the actual app. Example: Adobe Creative Cloud.

**Impact**: User gets an installer in /Applications instead of the actual app.

### 8. Multi-App DMGs We Detect, But User Expects One - Rating: 5/10 ✅ RESOLVED

A DMG might have "MyApp.app" and "MyApp Uninstaller.app". We detect 2 apps and fall back to manual, but the user expected us to just install the main app. False positive on our safety check.

**Impact**: Unnecessary fallback to manual installation for DMGs that could be handled automatically.

**Status**: RESOLVED in commit e841236 - Smart filtering now detects and filters out apps with "uninstall", "installer", "helper", or "readme" in the name, automatically installing the main app if exactly one remains.

### 9. Hidden .app Files - Rating: 3/10 ✅ RESOLVED

Some DMGs have hidden `.app` files (invisible in Finder) used for installation scripts. Our `find` command might catch these and incorrectly count as multiple apps.

**Impact**: Unnecessary fallback to manual installation.

**Status**: RESOLVED in commit e841236 - File scanning now filters out hidden files by checking `!item.hasPrefix(".")` when searching for .app bundles.

## First-Launch Behavior Issues

### 10. License Acceptance Recording - Rating: 5/10

Some apps record that they've been launched from a quarantined state and use that as implicit license acceptance. By removing quarantine before first launch, we might cause them to re-prompt for license acceptance.

**Impact**: Users might see license agreements they wouldn't normally see.

### 11. Analytics/Telemetry "Install Source" Detection - Rating: 7/10

Many apps track installation source (Mac App Store vs direct download vs Homebrew). They detect this via quarantine attributes or filesystem paths. By removing quarantine, we might cause analytics to misreport install source as "unknown" or "manual".

**Impact**: App developers get inaccurate analytics data; functionally harmless to users.

### 12. Auto-Updater Framework Assumptions - Rating: 8/10

Beyond Sparkle (which we fixed with quarantine removal), other update frameworks might have quirks:
- **Microsoft AutoUpdate** - Used by Office apps
- **Google Software Update** - Used by Chrome, Drive
- **Squirrel** - Used by Electron apps

Each might have different assumptions about quarantine, install paths, or first-launch detection.

**Impact**: Apps might show incorrect update prompts or fail to auto-update properly.

**Status**: Sparkle framework issue resolved by removing quarantine attributes. Other frameworks need testing.

## System Integration

### 13. LaunchAgents/LaunchDaemons Installation - Rating: 6/10

Apps that install background services (e.g., menu bar apps, sync daemons) typically do this on first launch. They might expect certain permissions or user prompts that don't appear if we've modified the installation path or attributes.

**Impact**: Background services might not install or start correctly on first launch.

### 14. Accessibility/Automation Permissions - Rating: 5/10

Apps requiring accessibility access (screen recorders, window managers) might behave differently if they detect they weren't launched "normally". macOS tracks which apps have requested permissions - if we change the app's path or attributes, permission grants might not transfer.

**Impact**: Previously granted permissions might not be recognized; apps might re-request permissions.

### 15. Hardened Runtime + Notarization Checks - Rating: 4/10 ✅ ADDRESSED

Notarized apps with Hardened Runtime enabled might perform additional validation on launch. While we're not modifying the app itself, changing when/how validation occurs might expose edge cases in the app's security checks.

**Impact**: Notarization validation might fail in unexpected ways.

**Status**: ADDRESSED in commit 15c060d - EasyDMG itself is now configured with Hardened Runtime and Developer ID notarization, ensuring compatibility with notarized apps and preventing potential conflicts.

## User Environment Edge Cases

### 16. Case-Sensitive APFS Volumes - Rating: 2/10

macOS defaults to case-insensitive APFS, but some developers use case-sensitive volumes. Apps that assume case-insensitive might break (e.g., looking for `Resources/icon.icns` when file is `Resources/Icon.icns`). Not our fault, but we'd be the visible trigger.

**Impact**: Apps might crash or fail to find resources on case-sensitive volumes.

### 17. Non-Standard /Applications Locations - Rating: 3/10 ⚠️ PARTIALLY RESOLVED

Some users have `/Applications` as a symlink, network mount, or on external drive. FileManager.copyItem might behave unexpectedly, or apps might not expect to be on external/network storage.

**Impact**: Copy failures, permission issues, or apps refusing to run from network storage.

**Status**: PARTIALLY RESOLVED in commit e841236 - Added validation to check that /Applications exists, is a directory, and is writable before attempting installation. This prevents silent failures but doesn't handle all non-standard cases (symlinks, network mounts still untested).

### 18. Insufficient Disk Space During Copy - Rating: 7/10 ✅ RESOLVED

If /Applications is on a volume with insufficient space, copyItem could fail partway through, leaving a corrupted partial app. We check for errors, but do we check available space beforehand?

**Impact**: Partial app installation that fails to launch; potential disk space waste.

**Status**: RESOLVED in commit e841236 - Pre-installation disk space check now calculates app bundle size and verifies sufficient space (app size + 500MB buffer) before copying. Shows clear error message with required space if insufficient.

## Performance & Resource Issues

### 19. Huge Apps (>10GB) - Rating: 6/10

Apps like Xcode, Adobe apps, or games can be massive. Long copy times might make users think EasyDMG froze. Also, our synchronous copy blocks the main thread - progress bar won't update smoothly for huge apps.

**Impact**: Poor UX during installation; potential timeout issues; frozen progress indicators.

### 20. Apps with Millions of Small Files - Rating: 4/10

Some apps (especially Electron apps with node_modules) have thousands of tiny files. FileManager.copyItem is file-by-file, which could be slow. Also increases chance of permission errors or filesystem issues.

**Impact**: Very slow installation; potential timeout or permission issues.

---

## Priority Issues to Investigate

Based on likelihood and impact, these issues should be prioritized:

1. **Symlink preservation** (#4, 8/10) - Easy to test, critical if broken
2. **Auto-updater frameworks beyond Sparkle** (#12, 8/10) - Fix might not cover all frameworks (Sparkle resolved, others need testing)
3. **Analytics/telemetry** (#11, 7/10) - Won't break functionality but might confuse developers
4. **App translocation** (#1, 7/10) - Could cause confusing UX
5. **Large apps** (#19, 6/10) - UX issue with progress indication
6. **PKG installers masquerading as apps** (#7, 6/10) - Wrong app gets installed
7. **XPC services and helper tools** (#5, 6/10) - Background services might not work correctly

## Resolved Issues

### Quarantine Attribute Causing False Update Detection (Fixed)

**Issue**: FileManager.copyItem() propagated quarantine attributes from downloaded DMGs to installed apps, causing apps with auto-update mechanisms (like Sparkle framework) to incorrectly detect "needs update" state.

**Solution**: Remove quarantine attributes after installation using `xattr -dr com.apple.quarantine`, replicating manual Finder drag-and-drop behavior.

**Commit**: 817ac2b (main), 79a5fbe (feature/settings-window)

### Smart Multi-App Detection (#8 - Fixed)

**Issue**: DMGs containing both main apps and uninstallers/helpers would trigger manual installation fallback unnecessarily.

**Solution**: Implemented smart filtering that identifies and excludes apps with "uninstall", "installer", "helper", or "readme" in their names. If exactly one main app remains after filtering, it's automatically installed.

**Commit**: e841236

### Hidden .app Files (#9 - Fixed)

**Issue**: Hidden .app files (starting with `.`) could be detected and cause false multi-app detection.

**Solution**: File scanning now filters out hidden files by checking `!item.hasPrefix(".")`.

**Commit**: e841236

### Insufficient Disk Space (#18 - Fixed)

**Issue**: Copying large apps without checking available space could result in partial installations and corrupted apps.

**Solution**: Pre-installation validation now calculates app bundle size and checks for sufficient free space (app size + 500MB buffer), showing clear error messages if insufficient.

**Commit**: e841236

### /Applications Folder Validation (#17 - Partially Fixed)

**Issue**: Non-standard /Applications configurations (symlinks, network mounts, external drives) could cause silent failures.

**Solution**: Added validation to verify /Applications exists, is a directory, and is writable before installation. Symlinks and network mounts still need testing.

**Commit**: e841236

### Hardened Runtime Compatibility (#15 - Addressed)

**Issue**: EasyDMG interactions with notarized apps using Hardened Runtime could expose edge cases.

**Solution**: EasyDMG itself is now configured with Hardened Runtime and Developer ID notarization, ensuring full compatibility with notarized apps.

**Commit**: 15c060d

---

*Last updated: 2026-01-19*