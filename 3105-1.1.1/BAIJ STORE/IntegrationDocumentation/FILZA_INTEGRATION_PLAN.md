# Filza Integration Plan

## Current Phase

Preparation only. No Filza code, WQFiles code, dependency, framework, entitlement, hook, private API, or filesystem-access implementation is integrated. The router and adapter contract are not connected to app operations.

## Future Review Sequence

1. Inventory each proposed upstream component and record its source, license, version, and provenance.
2. Audit imports, linked frameworks, transitive dependencies, private APIs, hooks, entitlements, sandbox assumptions, filesystem/container access, native/kernel boundaries, OS availability, and concurrency behavior.
3. Reject components requiring unapproved private APIs, hooks, WQFiles imports, or sandbox-evasion behavior; do not infer support from jailbreak status.
4. Implement only reviewed adapter capabilities and initialization checks, with tests for supported/unsupported OS versions and unavailable adapters.
5. In a separate change, bridge the original `ExploitSupportPolicy` into the router. Preserve the current original-engine route for supported systems and fail closed with an explicit unsupported-engine state when neither engine is available.
6. Review Xcode source membership and security/configuration changes independently before enabling any operation routing.

`Engines/FilzaAdapter/FilzaSource/` is reserved for reviewed source only and remains outside the compile phase until an explicit integration change.
