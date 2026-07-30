# Local Tooling

Required for the current scaffold:

- Node.js 22+
- Bun 1.3+
- Terraform CLI on `PATH` as `terraform`
- Optional: OpenTofu for reviewing/applying synthesized output after CDKTN has generated it
- Optional: `talosctl` for Talos machine configuration
- Optional: `kubectl`, `helm`, and `argocd` for cluster bootstrap and debugging
- Optional: `aws` and `openssl` for IAM Roles Anywhere DNS automation bootstrap
- Optional: `curl` for registering Talos image-factory schematics

Current workspace check:

- `node --version` succeeded with Node 22.
- `bun --version` succeeded with Bun 1.3.14.
- `terraform version` succeeded with Terraform 1.15.8.
- `tofu version` failed because OpenTofu is not installed.

CDKTN needs a `terraform` executable for `bun run get`.

The Proxmox scripts load local settings from the repo root `.env`. Start from `.env.example` and keep real tokens out of Git.
