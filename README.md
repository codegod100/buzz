# Buzz (Nix flake)

Build [block/buzz](https://github.com/block/buzz) from source with Nix.

Pinned to commit `e9188c03f6c2460983a3dac0fa7702b468838e62` (desktop release **v0.4.22**).

## Packages

| Attr | What you get |
|------|----------------|
| `.#default` / `.#buzz` | `buzz-relay`, `buzz-admin`, `buzz-pair-relay` + web/admin-web static assets |
| `.#server` | Rust server binaries only |
| `.#cli` | `buzz` CLI (agent-first, JSON in/out) |
| `.#tools` | `buzz-acp`, `buzz-agent`, `buzz-push-gateway`, `buzz-dev-mcp` |
| `.#web` | Static `web` + `admin-web` bundles |

## Build

```bash
nix build .#          # full relay + web UI
nix build .#server
nix build .#cli
nix build .#web
```

Run the relay (needs Postgres + Redis; see upstream `docker-compose.yml`):

```bash
nix run .#
# or
./result/bin/buzz-relay
```

`buzz-relay` is wrapped with:

- `BUZZ_WEB_DIR` / `BUZZ_ADMIN_WEB_DIR` pointing at the bundled UI
- `git` on `PATH` (git hydrate / pack operations)
- system CA bundle for TLS

## Dev shell

```bash
nix develop
```

Provides Rust 1.95, Node 24, pnpm 11, just, sqlx-cli, protobuf, etc.

## Updating the pin

1. Bump `rev` / `version` in `flake.nix`.
2. Refresh the source hash (`nix build` will print the new one).
3. Replace `./Cargo.lock` with upstream’s lockfile for that rev.
4. Refresh the `fetchPnpmDeps` hash under `buzz-web`.

## Runtime requirements

The relay expects:

- PostgreSQL (`DATABASE_URL`)
- Redis (`REDIS_URL`)

Defaults and the rest of the env surface are documented in upstream `.env.example`.
