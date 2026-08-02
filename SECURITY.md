# Security Policy

`open-homelab` includes infrastructure code, bootstrap scripts, and Kubernetes manifests. Treat local deployments as security-sensitive even when they run only on a LAN.

## Supported Versions

Security fixes target the `main` branch.

## Reporting A Vulnerability

Please do not open a public issue for a vulnerability that exposes credentials, weakens authentication, grants unintended cloud permissions, or allows cluster compromise.

Use GitHub private vulnerability reporting if it is enabled for the repository. If it is not enabled, contact the maintainers through the repository owner profile and include:

- affected file or component
- impact
- reproduction steps
- suggested fix, if known

## Secret Handling

Never commit:

- `.env`
- Talos `secrets.yaml`
- generated kubeconfigs or talosconfigs
- OpenTofu state
- OpenBao unseal keys, recovery keys, root tokens, or app secrets
- IAM Roles Anywhere private keys and certificates
- Proxmox API tokens

## Deployment Responsibility

This repo is a template for self-hosted infrastructure. You are responsible for reviewing manifests, cloud permissions, exposed hostnames, ingress rules, and backup policy before deploying it on your network.
