# Filza Adapter Boundary

This folder contains only contracts and compatibility metadata. No Filza source, WQFiles code, filesystem implementation, private API, hook, entitlement, or dependency is included.

`FilzaEngineAdapter` is a declaration-only contract. A future adapter must declare its initialization state, supported iOS ranges, and capabilities before the disconnected `OSCompatibilityRouter` can select it. Selection alone does not execute filesystem operations.

Before adding each upstream component, audit its license and provenance, imports and linked frameworks, transitive dependencies, private API use, hooks, entitlements, sandbox assumptions, filesystem and container access, kernel/native code, platform availability, and thread-safety. Reject or separately review components that rely on WQFiles, private APIs, hooks, or sandbox-evasion mechanisms. Do not copy upstream files into this target until that review and a separate integration task are approved.
