# Local Tooling

Required for the current scaffold:

- Node.js 22+
- Bun 1.3+
- OpenTofu CLI on `PATH` as `tofu`
- Optional: `talosctl` for Talos machine configuration
- Optional: `kubectl`, `helm`, and `argocd` for cluster bootstrap and debugging
- Optional: `aws` and `openssl` for IAM Roles Anywhere DNS automation bootstrap
- Optional: `curl` for registering Talos image-factory schematics

Current workspace check:

- `node --version` succeeded with Node 22.
- `bun --version` succeeded with Bun 1.3.14.
- `tofu version` should report OpenTofu 1.10 or newer.

CDKTN needs a `tofu` executable for `bun run get` (the Bun scripts set `TERRAFORM_BINARY_NAME=tofu`).

The Proxmox scripts load local settings from the repo root `.env`. Start from `.env.example` and keep real tokens out of Git.
