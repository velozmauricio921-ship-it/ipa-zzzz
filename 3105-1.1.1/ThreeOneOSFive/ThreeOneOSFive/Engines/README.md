# Discovery Engines

Engine selection is kept separate from file-source routing. The selection policy reports a motor and its implementation status; it does not initialize privileged components or change the existing browser.

- `Original3105/` documents the existing engine boundary. Its implementation remains in its current files and is not copied or refactored here.
- `FilzaAdapter/` is scaffolding only. It currently reports `notImplemented` and returns no discovered items.

No engine in this structure grants permissions. File access must come from the app sandbox or an explicit user-approved document URL.