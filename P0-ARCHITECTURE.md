# P0 architecture contract

## Channels

- MethodChannel: `qq_bot_cp/runtime`
  - `startRuntime`
  - `stopRuntime`
  - `restartRuntime`
  - `getRuntimeState`
  - `getPublicConfig`
- EventChannel: `qq_bot_cp/runtime_events`
  - runtime state events
  - structured log events
  - network events
  - update progress events

The Flutter layer never receives raw secrets. Native Android code reads Keystore-backed credentials and passes them only to the Runtime process.
