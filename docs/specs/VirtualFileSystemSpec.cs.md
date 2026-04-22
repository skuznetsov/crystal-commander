# Virtual File System CodeSpeak

## Intent

Commander must treat local disks and remote providers (SSH/SFTP/S3) uniformly so panels, commands, plugins, and automation see only URIs and provider operations. The design keeps auth secrets outside Crystal, supports graceful offline/cached behavior, and preserves familiar local command semantics during remote navigation. Implementation occurs in safe, verifiable stages with no network calls required for the first increment.

## MUST

- Every location in PanelState, history, bookmarks, and command arguments MUST be a URI with one of the registered schemes: file, ssh, sftp, s3.
- A VfsRegistry MUST dispatch all file operations to the provider registered for the URI scheme; unknown schemes MUST raise before any I/O.
- The provider interface MUST expose exactly these operations: stat, list, read, write, mkdir, delete, rename, copy, open_stream.
- Auth credentials and private keys MUST never reside in Crystal process memory longer than the duration of a single provider call or an explicit short-lived session handle.
- Providers MUST surface typed VfsError values (NotFound, PermissionDenied, AuthFailed, NetworkError, Offline, UnsupportedOperation, QuotaExceeded, UnsupportedScheme) rather than strings or exceptions that leak implementation details.
- Panel navigation (cd, up, goto, ~ expansion) MUST resolve relative segments against the current URI using the owning provider; the resulting URI MUST be stored as the panel location.
- All local command semantics (mkdir foo, cp bar baz, rm -r, rename) MUST continue to work when the current location is remote; cross-provider operations MUST be coordinated by Commander core using read/write or native provider copy when available.
- Caching MUST be provider-supplied and optional; metadata cache entries MUST carry a staleness flag when served offline.
- The first implementation increment (Phase 0) MUST introduce the URI abstraction and FileProvider wrapper with zero new dependencies and zero network code paths.
- Verification suites that exercise URI parsing, registry dispatch, mock providers, error paths, and offline simulation MUST run without any real network credentials or external services.

## MUST NOT

- Commander core, commands, or plugins MUST NOT contain scheme-specific if/else or string prefix checks; all behavior MUST be obtained via VfsProvider.
- Private keys, access secrets, session tokens, or passwords MUST NOT be serialized into logs, crash reports, automation payloads, snapshots, or persisted PanelState.
- Mutating operations (write, mkdir, delete, rename) MUST NOT succeed in offline mode; they MUST fail with VfsError::Offline.
- Remote providers MUST NOT be instantiated or connected during application startup or spec_check runs.
- The design MUST NOT introduce new runtime dependencies (no new shards for SSH/S3 in Phase 0).
- GUI smoke tests or the macOS app binary MUST NOT be launched as part of VFS verification.

## URI Schemes and Examples

- file: URI
  - Canonical form: file:///absolute/path/to/resource
  - Example: file:///Users/sergey/Projects/Crystal/commander/README.md
  - Relative or bare paths emitted by user input are normalized to file: URIs at the boundary.
  - Home directory: file://$HOME expands via provider home resolution.

- ssh: URI (interactive shell / exec)
  - Form: ssh://[user@]host[:port][/path]
  - Example: ssh://sergey@bastion.example.com:2222/home/sergey/src
  - Port defaults to 22. User defaults to $USER or provider policy.
  - Path is absolute on the remote; no implicit ~ unless provider resolves it.

- sftp: URI (file transfer over SSH)
  - Form: sftp://[user@]host[:port][/path] (identical structure to ssh)
  - Example: sftp://sergey@bastion.example.com/var/www/html
  - Preferred for directory browsing and bulk transfer; ssh: used for command execution when needed.
  - Host-key verification and known_hosts handling are mandatory.

- s3: URI (object storage)
  - Form: s3://bucket[/key/prefix]
  - Example: s3://my-backups/2026-04-10/logs/
  - Bucket names follow AWS rules; keys use / as delimiter. Leading / after bucket is normalized away.
  - Region may be supplied via provider configuration or derived from endpoint; never embedded in every URI.

All URIs MUST round-trip through parse/serialize without loss. Relative resolution (append segment, .. parent) is performed by a shared UriResolver that delegates scheme-specific home/parent rules to the provider.

## Provider Interface Operations

```crystal
# Pseudocode for the contract (actual types live in future src/vfs/provider.cr)
abstract class VirtualFileSystemProvider
  abstract def scheme : String

  abstract def stat(uri : URI) : Result(FileInfo, VfsError)
  abstract def list(uri : URI, opts : ListOpts = ListOpts.new) : Result(Array(FileInfo), VfsError)
  abstract def read(uri : URI) : Result(Bytes, VfsError)          # small files; prefer open_stream for large
  abstract def write(uri : URI, data : Bytes, opts : WriteOpts) : Result(Nil, VfsError)
  abstract def mkdir(uri : URI, recursive : Bool = false) : Result(Nil, VfsError)
  abstract def delete(uri : URI, recursive : Bool = false) : Result(Nil, VfsError)
  abstract def rename(src : URI, dst : URI) : Result(Nil, VfsError)
  abstract def copy(src : URI, dst : URI, opts : CopyOpts = CopyOpts.new) : Result(Nil, VfsError)
  abstract def open_stream(uri : URI, mode : AccessMode) : Result(IO::Stream, VfsError)

  # Optional
  def supports(operation : Symbol) : Bool
  def close_session : Nil   # release auth handles, clear short-term caches
end

struct FileInfo
  name : String
  size : UInt64
  mtime : Time
  is_directory : Bool
  permissions : PermissionBits
  owner : String?
  group : String?
  provider_meta : Hash(String, String)   # e.g. s3 storage class, ssh inode
end
```

FileInfo and error types are stable across providers. list and stat populate provider_meta only for debugging/telemetry; core logic ignores it.

## Auth Boundary and Secret Handling Rules

- Every provider is constructed with an AuthContext supplied by the UI or automation layer.
- SSH/SFTP providers MUST obtain credentials exclusively via:
  - ssh-agent socket (SSH_AUTH_SOCK)
  - macOS Keychain items of kind "SSH key" or "internet password"
  - One-time passphrase prompt via secure UI field (result zeroed after use)
- S3 providers MUST obtain credentials via:
  - AWS_PROFILE / instance metadata / STS assume-role (temporary)
  - External credential_process (never read secret files directly)
  - macOS Keychain "AWS access key" entries
- No provider constructor accepts raw secret bytes or long-lived access keys as parameters.
- Session handles returned to callers are opaque tokens; the real secret material stays inside the provider's native library (libssh2, AWS CRT, etc.).
- On any error or explicit logout, providers MUST call close_session to drop handles.
- Automation payloads and snapshots MUST contain only redacted URI strings (user@host/path without credentials).
- Logs and VfsError messages MUST be free of any substring that could be a key, token, or password.

## Caching / Offline / Error Model

- Providers MAY expose a CacheController with:
  - metadata_ttl : Duration (default 30s for remote, 0 for local)
  - content_cache_max_bytes : UInt64 (opt-in, default 0)
- When offline (no route or explicit offline flag), list/stat return cached FileInfo with .stale = true. Mutating calls immediately return VfsError::Offline.
- Background refresh: active remote panels register for periodic or on-focus refresh; results arrive as asynchronous PanelRefresh events.
- Retry policy for NetworkError(retryable=true): exponential backoff 100ms, 500ms, 2000ms (max 3 attempts) inside the provider before surfacing the error.
- VfsError is never swallowed by core; every command surface receives the code and a user-facing message.
- Cache invalidation occurs on successful write/delete/rename from any provider instance sharing the same root URI.

## Panel Navigation While Preserving Local Command Semantics

- PanelState.current_location : URI replaces the former String path.
- Navigation primitives:
  - cd <segment> → resolve URI + segment via provider.resolve or UriResolver.append
  - cd .. → provider.parent(current) or pop last segment
  - cd ~ → provider.home(current.scheme) or file://$HOME
  - goto <full-uri> → parse, validate scheme registered, set location
- Command dispatch always extracts the provider for the target URI(s):
  - Single-provider ops (most) call provider.mkdir etc.
  - Cross-provider copy/move: core performs streaming read + write with progress callback; if both providers support native copy it is used.
- Display: file: URIs pretty-print as local paths; remote URIs show scheme://user@host/path or a short alias from connection manager.
- Selection, filtering, sorting, and quick-look remain identical regardless of scheme.
- History stack stores full URIs; back/forward replay the exact remote location.
- Plugin and automation APIs receive URIs and must use Commander file operations rather than direct FS calls.

## Lua Plugin Access

- Lua plugins MUST access VFS only through Commander-mediated APIs, never by loading SSH/S3 libraries directly.
- The current Lua VFS increment exposes permission-gated URI parsing only:
  - `commander.vfs.parse(uri)`
  - `commander.vfs.allowed_schemes()`
  - `commander.vfs.request(operation, uri, target_uri)`
- The next Lua VFS surface SHOULD be read-only and permission-gated:
  - `commander.vfs.stat(uri)`
  - `commander.vfs.list(uri)`
  - `commander.vfs.read_text(uri, opts)`
  - `commander.vfs.mount(alias, uri)`
- `commander.vfs.parse(uri)` MUST return either a copied URI table (`scheme`, `authority`, `path`, `uri`) or a typed error table.
- `commander.vfs.parse(uri)` MUST require `vfs.read:<scheme>` or `vfs.read:*` before returning URI metadata for that scheme.
- `commander.vfs.allowed_schemes()` MUST return only schemes granted by the plugin manifest.
- `commander.vfs.request(operation, uri, target_uri)` MUST return a Commander-mediated intent action; Lua MUST NOT execute provider I/O directly.
- Mutating Lua VFS operations (`write`, `mkdir`, `delete`, `rename`, `copy`) MUST require manifest permissions and Commander confirmation policy.
- Lua VFS results MUST be copied snapshots or JSON-like tables; Lua MUST NOT receive provider handles, raw streams, credentials, or AppKit/C ABI pointers.
- Lua VFS calls MUST return typed error tables with VfsError codes, not raw exception messages.
- Lua plugin manifests MUST declare VFS permissions explicitly, for example:
  - `vfs.read:file`
  - `vfs.read:sftp`
  - `vfs.read:s3`
  - `vfs.write:file`
  - `vfs.write:sftp`
  - `vfs.write:s3`
- VFS permissions are additive; `panel.read` does not imply remote VFS access.
- Credential prompts for Lua-initiated remote access MUST be performed by Commander UI/automation, not Lua.
- Lua automation MUST be able to operate on mounted aliases so scripts can avoid embedding remote hostnames or bucket names in source code.

## Staged Implementation Plan with Safe First Increment

Phase 0 — URI Abstraction & Local Provider (SAFE FIRST INCREMENT)
- Introduce URI value type and VfsRegistry.
- Implement FileProvider that translates file: URIs to existing local file_operations.cr calls.
- Change PanelState, command args, and renderer display logic to carry URIs (display layer strips file: prefix for local paths).
- All existing commands, specs, and smoke tests continue to pass unchanged.
- No new shards, no network code, no macOS keychain calls.
- Risk: LOW. Rollback cost: single module revert. Verification: pure local + mocks.

Phase 1 — Connection Manager + Mock Remote Provider
- Add MockVfsProvider for deterministic testing of dispatch, error, and offline paths.
- Create SSH/SFTP provider skeleton using existing system ssh/sftp binaries or libssh2 (behind compile flag).
- Connection manager stores host aliases, verifies host keys, caches session handles.
- Address bar and "Connect" command accept ssh:// and sftp:// URIs.
- Still no S3; remote panels visible only when developer supplies a mock.
- Lua read-only VFS API can be tested against MockVfsProvider with no credentials.

Phase 2 — S3 Provider + Unified Progress
- Implement S3Provider using AWS SDK or pure Crystal HTTP + SigV4 (or external credential helper).
- Add transfer progress events consumable by UI and automation.
- Cross-provider copy (local ↔ s3) exercises the streaming path.

Phase 3 — Caching Layer, Offline UX, Polish
- Shared VfsCache service with TTL and size bounds.
- Offline banner and stale-data indicators in panels.
- Background refresh, change notifications (future), and credential refresh flows.
- Full verification matrix including real-but-ephemeral test accounts (optional).

Exit criteria for each phase: spec_check passes, no credential material in repo, all new code covered by mock-based tests, documentation in this spec updated if contract changes.

## Verification Checks (No Real Network Credentials Required)

1. URI round-trip and resolution tests
   - parse("file:///a/b"), parse("ssh://u@h:22/p"), parse("s3://b/k"), serialize equals input.
   - resolve(current="ssh://u@h/dir", rel="..") == "ssh://u@h"
   - resolve(current="file:///home/u", rel="~") yields provider.home result.

2. Registry dispatch and interface compliance
   - Register FileProvider and MockProvider.
   - For every operation (stat/list/read/write/mkdir/delete/rename/copy/open_stream) invoke via registry and assert correct provider received the call.
   - Unknown scheme ("ftp://") raises VfsError::UnsupportedScheme before any I/O.

3. Error model coverage
   - MockProvider can be configured to return each VfsError variant; verify typed handling and user messages.
   - Offline mode test: list returns stale entries; write/delete raise Offline.

4. Auth boundary static and runtime checks
   - Grep for any struct or method parameter containing "secret", "key", "password", "token" in vfs/ sources — must be absent or explicitly redacted.
   - Construct providers only with opaque AuthContext; assert no raw bytes flow into Crystal heap in test harness.

5. Panel navigation simulation
   - Create PanelState with file: URI, perform cd, verify location updates and provider.list invoked.
   - Switch to ssh: URI (mock), repeat; assert scheme preserved and commands still dispatch.

6. Cross-provider operation test
   - Two mock providers (local-like and remote-like).
   - Execute copy from one to the other; verify read on source + write on target sequence, progress callbacks, and final equality.

7. No-network guarantee
   - Running the VFS test suite must succeed with airplane mode or blocked DNS; only file: and mock providers are exercised.
   - spec_check (this script) continues to pass with zero Cyrillic and required headings present.

8. Documentation hygiene
   - All prose in docs/specs/VirtualFileSystemSpec.cs.md and updated TODO.md must be English.
   - No new files created outside docs/specs/ and TODO.md for this design task.

## Invariants

- The VFS layer is the single source of truth for file existence and mutability; direct Crystal File or Dir calls outside tests are forbidden after Phase 0.
- Provider instances are cheap to create but sessions are reference-counted; close is explicit.
- URI equality is scheme + host + port + normalized path; query and fragment are unsupported for file locations.
- Display strings for remote URIs MUST NOT contain secrets even in redacted form beyond user@host.

## Checks

- Before any Phase N implementation begins, re-read this spec and confirm the staged plan still matches reality.
- Any addition of a new scheme or operation requires an update to this document in the same change.
- Before merging remote-provider code, run the full verification list above (mock-only) and attach output to the PR.
- Inspect specs/PanelsAndEventsSpec.cs.md and specs/ArchitectureSpec.cs.md for interaction with panel location changes.
- Run `sh scripts/spec_check` after every edit to docs/specs/VirtualFileSystemSpec.cs.md or TODO.md; it must exit 0.
- Lua VFS permission checks must be covered by mock-provider tests before any real SSH/SFTP/S3 provider is enabled.
