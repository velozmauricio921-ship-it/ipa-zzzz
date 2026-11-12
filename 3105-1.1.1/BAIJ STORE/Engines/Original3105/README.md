# Original 3105 Engine

This folder documents the existing engine boundary; it does not duplicate or move engine code.

Protected original entry points and dependencies identified for this preparation:

- `ThreeOneOSFive/App.swift`: `AppState.detectSupport`, support status, and kernel-exploit dispatch.
- `ThreeOneOSFive/helpers/SupportPolicy.swift`: configured iOS/build compatibility policy.
- `ThreeOneOSFive/helpers/KernelExploit.swift`: exploit applicability, status, and execution.
- `ThreeOneOSFive/helpers/ContainerStore.swift`: original container discovery and filesystem operations.
- `ThreeOneOSFive/ThreeOneOSFive-Bridging-Header.h`, `ThreeOneOSFive/exploit/`, and `ThreeOneOSFive/kexploit/`: native bridge and exploit dependencies.

All existing engine sources, services, filesystem/sandbox access mechanisms, UI, permissions, and configuration remain protected. The new router is not connected to these files. Any future integration requires a separate review and explicit wiring change.
