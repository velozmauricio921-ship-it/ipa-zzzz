# WQ component integration notes

The WQ source files are not currently part of the 3105 Xcode target. The Swift adapters report them as absent and do not call WQ functions. Adding source files to a target is not evidence that private APIs work or that the app has permission to access a location.

## Manual copy map

Copy only after reviewing the upstream license and the restrictions in this document.

| Original source in `WQFiles-main(1)/WQFiles-main/` | Proposed destination under `3105-1.1.1/ThreeOneOSFive/helpers/WQIntegration/` |
|---|---|
| `WQAccess.h` | `WQAccess/WQAccess.h` |
| `WQAccess.m` | `WQAccess/WQAccess.m` |
| `WQAccessSafety.h` | `WQAccess/WQAccessSafety.h` |
| `WQLaunchServices.h` | `WQLaunchServices/WQLaunchServices.h` |
| `WQLaunchServices.m` | `WQLaunchServices/WQLaunchServices.m` |
| `WQCore.h` | `Support/WQCore.h` |
| `WQCore.m` | `Support/WQCore.m` |
| `WQLocalization.h` | `Support/WQLocalization.h` |
| `WQLocalization.m` | `Support/WQLocalization.m` |

`WQAccess.h` imports `WQLaunchServices.h`; `WQLaunchServices.m` imports `WQAccess.h`; and `WQAccess.m` imports `WQCore.h`, `WQAccessSafety.h`, and `WQLocalization.h`. Both implementations also use functions from the other module. These nine source/header files form the minimum source dependency set visible from the checked-in imports. `WQAccessSafety.h` is header-only. Do not copy just the five requested files and assume the result is self-contained.

The source imports Foundation and system headers. WQFiles' `build.sh` links UIKit, Foundation, Security and UniformTypeIdentifiers and also links sqlite3 and zlib for the complete WQFiles executable. That full-app link line is not proof that all those libraries are needed by only these two modules; re-evaluate linker requirements on macOS after source review. WQAccess also dynamically resolves private system symbols, so successful linking cannot establish runtime availability.

## Actual Objective-C interfaces

These modules do not declare a shared Objective-C service class. Their public headers expose C functions.

- `WQAccess.h` exports `wq_app_group`, `wq_grant`, `wq_list`, `wq_read`, `wq_file_version`, the `wq_write*`/`wq_patch*` mutation functions, `wq_create_*`, `wq_delete*`, `wq_rename`, `wq_move`, `wq_stat`, `wq_enumerate`, `wq_measure_tree`, `wq_purge_contents*`, `wq_copy_contents`, backup helpers, and callback setters. It declares `WQScanCancellation`, an Objective-C class with atomic readonly property `cancelled` (getter `isCancelled`) and method `-cancel`; it also declares `WQMeasureResult` and uses `struct stat` from `<sys/stat.h>`.
- `WQLaunchServices.h` exports `wq_display_name`, `wq_bundle_id_for_container`, `wq_display_names_loaded`, `wq_load_display_names`, `wq_display_names_reset_miss`, `wq_ls_container_paths`, `wq_bundle_path_for_id`, and `wq_ls_bundle_containers`. It declares no Objective-C classes.
- `WQAccessSafety.h` contains static inline C helpers; it declares no Objective-C class or runtime API.

The current Swift adapters intentionally do not declare forwarding methods for these functions. This avoids inventing Swift signatures for nullable double-pointers, blocks, C structs, and Objective-C imported names, and avoids making calls into the privileged/private implementation. After a permitted API surface is approved, write a narrow wrapper against the imported declarations and validate it with Xcode; do not infer a Swift name from the C spelling.

## Xcode and Objective-C/Swift

No WQ Objective-C source or header reference is present in `project.pbxproj` yet. This is intentional: adding PBX references before the user copies those files would create a broken target.

The existing bridging header is `ThreeOneOSFive/ThreeOneOSFive-Bridging-Header.h`; no replacement is needed. It currently imports 3105's existing exploit/helper headers and remains unchanged. Do not import `WQAccess.h` or `WQLaunchServices.h` into it: their interfaces expose private/privileged behavior and database parsing. If a separately reviewed, documented public subset is approved later, expose only that subset through a narrow wrapper rather than bridging the WQ headers wholesale.

After those sources actually compile into the app target, define `WQ_ACCESS_COMPONENT_LINKED` and/or `WQ_LAUNCH_SERVICES_COMPONENT_LINKED` in the target's Swift Active Compilation Conditions to make diagnostics report the corresponding component as linked but unavailable. These flags do not enable calls. The adapters keep `functionalityEnabled` false; there is no runtime probe for private symbols, token issuance, or container access.

3105 already has `ThreeOneOSFive/ThreeOneOSFive-Bridging-Header.h`, configured by `SWIFT_OBJC_BRIDGING_HEADER`. Its current imports are unrelated exploit and helper headers. The project enables Objective-C ARC, uses Swift 5.0, GNU C17, and an iOS 16 deployment target. Its app target's Frameworks build phase is empty and `OTHER_LDFLAGS` contains `-lz`. The WQ headers have a circular module dependency: `WQAccess.h` imports `WQLaunchServices.h`, and `WQLaunchServices.m` imports `WQAccess.h`. No WQ import or header search path is added to 3105 by this preparation.

WQAccess uses Foundation and system headers, plus Security APIs for entitlement inspection; its source dynamically resolves system/private symbols. Foundation and Security are the first framework dependencies to verify for these two modules. WQFiles' complete app build additionally links UIKit, UniformTypeIdentifiers, sqlite3 and zlib for other app modules; do not add every full-app dependency without a target-level link check. Keep ARC enabled, matching WQFiles' `-fobjc-arc` build. Do not add entitlements, change the bundle identifier, or change signing automatically. WQFiles' `entitlements.plist` declares `com.apple.security.application-groups` with `group.cz.kolbi.wqfiles`; that group must be explicitly available in the chosen provisioning profile for WQFiles' implementation. BAIJ STORE does not currently have that entitlement. An App Group grants access only to that shared group; it does not authorize access to other apps' private containers.

## Capability boundary

`WQAccess.m` contains private/privileged access and container enumeration code. `WQLaunchServices.m` parses LaunchServices' private on-disk database and uses layouts that vary by iOS release. Their matching headers and symbols are not public iOS APIs. The WQ adapters deliberately report functionality unavailable even if a future build links the sources. They do not call those APIs, probe for permissions by attempting access, or turn discovery results into file access.

Keep these functions disabled in BAIJ STORE unless a separately reviewed, authorized implementation is available:

- Enumerating other apps' data containers or their parent directories.
- Resolving private container paths through LaunchServices or MobileContainerManager internals.
- Obtaining or consuming sandbox extensions for other apps' files.
- Scanning filesystem object IDs to discover protected paths.
- Mutating or restoring files outside BAIJ STORE's own storage, a signed App Group, or a user-selected security-scoped URL.

`preparedAndVerified` must mean that the exact capability was tested on the supported device and that its required permission was independently confirmed. A linked object file, an App Group entitlement, an app identifier, or an app name is not that verification.

## License and distribution review

WQFiles states that it is licensed under GPL-3.0-or-later. If WQ source is copied, modified, linked into BAIJ STORE, or distributed in an IPA, obtain legal review of whether the resulting work is covered and what source, license, attribution, notices, and corresponding-source obligations apply. Preserve the upstream copyright and license notices and include the license text if distribution proceeds under GPL. This note is not legal advice.

## Secret handling remains a release blocker

The current GitHub Actions workflow injects `KEYAUTH_SECRET` into the built `Info.plist` and prints that plist with `plutil -p`. The value is therefore exposed in build logs and the IPA. Removing it without a validated server-side authentication design would break the current client. Do not distribute new artifacts with that embedded client secret; rotate it if prior logs or artifacts were accessible, and migrate verification to a server-side design before changing the workflow.