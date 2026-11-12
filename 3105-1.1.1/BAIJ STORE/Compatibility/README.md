# Compatibility Routing

`OSCompatibilityRouter` is a pure, disconnected decision model. It receives the original 3105 compatibility check as a closure; it does not replace or call the app's existing selection path. No instance is created by the current application.

When a future integration is separately approved, the caller can adapt the original `ExploitSupportPolicy` check and pass an initialized Filza adapter. Until then, the current 3105 behavior remains authoritative and unchanged.
