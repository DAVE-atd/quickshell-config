# DMS compatibility layer

`Common/`, `Services/` and `Widgets/` at the repo root provide the parts of
DankMaterialShell's `qs.Common` / `qs.Services` / `qs.Widgets` API that
vendored DMS plugins (`src/vendor/orbitBluetooth`) use. Quickshell resolves
`qs.<dir>` against the config root, so they have to live here.

They map to Serpantinum's own theme and services. Only what the vendored
plugins call is implemented; most of the session/compositor services are
inert stand-ins (Hyprland, no DMS backend).
