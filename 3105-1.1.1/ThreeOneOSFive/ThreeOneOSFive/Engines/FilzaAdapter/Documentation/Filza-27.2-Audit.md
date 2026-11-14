# Filza 27.2 Component Audit

Scope: static review of the supplied `filza27.2-main(1).zip` and its checked-out source tree. No Filza code was copied or executed. The source README's iOS claims are not treated as independent compatibility evidence.

| Component | Purpose and dependencies | Classification and disposition |
|---|---|---|
| `WQFilzaIntegration.h/.m` | Filza-facing discovery, grants, roots, favorites, and metadata; imports `worse_query`, path/fallback helpers, MCM integration, and LaunchServices support. | Host-coupled orchestration. Not a standalone library; requires a documented-permission redesign before any reuse. Do not copy as-is. |
| `WQLSStore.h/.m` | LaunchServices/container catalog and metadata. Current file operations use Filza's grant integration and undocumented store details. | Some parsing concepts might be separable if fed through a permitted documented API; current implementation is not independent. No reuse until source API and license are reviewed. |
| `MCMBridge.h/.m` | Runtime bridge to ContainerManager entry points. | Private API/runtime-resolution dependency. Excluded from this adapter. |
| `MCMFilzaIntegration.h/.m` | Filza's MCM-backed virtual locations and container integration. | Private API plus Filza host assumptions. Not an independent provider; excluded. |
| `WQArchive.h/.m` | Archive extraction interface using libarchive. | Potentially separable as archive code, but unrelated to discovery and overlaps existing BAIJ archive functionality. Requires independent license and behavior review; not included. |
| `worse_query.h/.m` | The header identifies this as a sandbox-escape proof of concept. | Privileged access mechanism. Explicitly excluded; not a dependency to port. |
| `fallback_query.h/.m` | Fallback access implementation in the same access stack. | Low-level access dependency. Excluded; no implementation details are ported. |
| `Tweak.m` | Hooks/extends the Filza process and its UI/runtime. | Requires the Filza host and injected dylib infrastructure. Cannot serve as a standalone BAIJ engine; excluded. |
| `Makefile` | Builds `FilzaApplySandboxExt` using Theos and installs into the Filza process. | Build recipe for an injected tweak, not a BAIJ dependency manifest. Do not import into the Xcode app target. |

## Expected placement if a component is later approved

- `Sources/`: only a reviewed, host-independent implementation using documented APIs.
- `Headers/`: headers for that approved implementation; do not stage MCM, sandbox, or access-primitive headers here.
- `Resources/`: only resources proven necessary for the approved component.
- `Dependencies/`: dependency/license records; no vendored library is added now.
- `Compatibility/`: explicit, independently tested compatibility notes; do not copy README claims into the iOS policy.
- `Documentation/`: audit, provenance, API contracts, and test evidence.

## Build and external requirements observed

The Filza Makefile requires Theos, an iOS SDK, arm64, and produces a dylib tweak. It references UIKit/Foundation and other Apple frameworks, private `IOSurface`, system libraries including `archive`, and a vendored weak-linked `libssh`. Include paths reference XPF/ChOma. The README's packaging scripts require a compatible unsigned Filza base IPA; signing paths describe App Group entitlements and a provisioning profile. The developer build additionally expects an a-Shell IPA. These are not added as BAIJ requirements.

## License and provenance

The supplied tree has no general root license file in the inspected paths. `worse_query` declares GPL-3.0, `WQFilzaIntegration.m` labels its integration GPL-3.0, and `WQLSStore.m` labels itself GPL-3.0-or-later. The tree also contains vendored and separately licensed content. Review each file's provenance, applicable license, notices, and distribution obligations before considering any reuse; this document is not a legal determination.

## Required tests before any future adoption

- Compile an isolated, permission-only provider in the existing Xcode app target.
- Test provider-not-implemented, unavailable, permission-denied, enumeration-error, empty, and populated outcomes.
- Test security-scoped access lifecycle using URLs explicitly selected by the user, including release on errors and cancellation.
- Test that no source outside the granted URL or app sandbox is enumerated.
- Run the existing GitHub Actions build and device tests on each explicitly authorized OS/build.
- Re-review component licenses and verify no dependency on Filza's process, tweak loader, private APIs, or privileged access primitives remains.