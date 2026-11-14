# Integration Status

Status: not implemented.

- No Filza source, binary, framework, or dependency has been copied into BAIJ STORE.
- The adapter reports `EngineAvailability.notImplemented` with pending prerequisites.
- It advertises no discovery capabilities and returns an empty result only as an explicit `notImplemented` status, not as a successful empty scan.
- `MotorSelectionPolicy` may select this adapter for unverified versions, but does not execute it or claim iOS 27.2 support.
- Selection is informational only; existing views and `ContainerStore` are not connected to it.