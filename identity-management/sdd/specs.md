# Identity Management Specification

> **Change**: identity-management
> **Date**: 2026-05-29
> **Status**: Draft
> **Architecture**: AD (DC-VM) + FreeIPA cross-realm trust

## Purpose

Centralized identity, authentication, authorization, and DNS for Grupo Gidas across Proxmox nodes, containers, and services — using Active Directory as the user source and FreeIPA for Linux-native policy enforcement.

## Requirements

### R1: AD Domain Controller
The system SHALL maintain DC-VM as the AD domain controller. The domain MUST be resolvable from all hosts in 192.168.1.0/24.

### R2: FreeIPA Server
The system SHALL deploy a FreeIPA server on pve-ad (Rocky Linux 9, ≥2 GB RAM, ≥20 GB disk) with DNS (Bind), CA (Dogtag), HBAC, and sudo rule capabilities.

### R3: Cross-Realm Trust
The system MUST establish a cross-realm Kerberos trust between AD and FreeIPA. AD remains the authoritative identity source.

### R4: Linux Authentication
All Linux hosts (Proxmox nodes, containers) MUST authenticate via SSSD pointing to FreeIPA. SSSD MUST cache credentials for ≥8 h of offline authentication.

### R5: PVE Authentication
Proxmox VE MUST have a realm (AD or IPA) configured for centralized web UI and API login, with AD groups mapped to PVE roles.

### R6: Group Model
AD groups SHALL model subgrupos: `gidas-admins`, `gidas-rojo`, `gidas-azul`, `gidas-verde`, `gidas-amarillo`, `gidas-monitoring`. FreeIPA HBAC rules MUST restrict each group to its designated hosts.

### R7: Security
Secrets — AD passwords MUST be stored in `secrets/proxmox.yaml` encrypted with SOPS. The VM-DC1 admin password (`hlvs.2025`) MUST be rotated after initial setup. LDAP binds MUST use TLS (LDAPS, port 636). Kerberos ticket TTL MUST NOT exceed 24 h. No credentials MAY appear in plain text in any config file.

### R8: DNS
FreeIPA MUST be the primary DNS resolver for Linux hosts. AD DNS MUST serve as secondary/forwarder for Windows resolution. Both domains MUST be resolvable across 192.168.1.0/24.

### R9: Resilience
FreeIPA SHOULD have a replica if it becomes a critical-path dependency. SSSD offline cache MUST cover ≥8 h. AD credentials MUST NOT be stored in plain text.

### R10: Backup
FreeIPA backup MUST be configured via `ipa-backup`. AD backup MUST be configured via Windows Server Backup plus PVE snapshots.

### R11: Procedures
User onboarding (AD user creation → group assignment → access verification) and offboarding (AD user disable → HBAC rule cleanup) MUST be documented in `docs/`.

## Scenarios

### S1: SSH Authentication — Linux → SSSD → FreeIPA → AD

- GIVEN a Linux host with SSSD configured for FreeIPA
- AND a user exists in AD with membership in `gidas-rojo`
- WHEN the user authenticates via SSH
- THEN SSSD queries FreeIPA
- AND FreeIPA validates the Kerberos trust with AD
- AND FreeIPA applies HBAC rules
- AND the user is granted access only to permitted hosts

### S2: PVE Web UI Authentication — AD Realm

- GIVEN PVE configured with an AD realm and group-to-role mappings
- AND a user exists in AD with membership in a mapped group
- WHEN the user logs in to the PVE web UI
- THEN PVE authenticates via LDAP (or LDAPS) bind to AD
- AND the user receives the assigned PVE role permissions

### S3: New User Provisioning — AD → Linux Access

- GIVEN an admin with AD credentials stored in SOPS
- WHEN the admin creates a user in AD and assigns group membership
- AND SSSD cache refresh interval elapses (or `sss_cache -E` is run)
- THEN the user can SSH into hosts permitted by the group's HBAC rule

### S4: Host Access Restriction — HBAC Enforcement

- GIVEN a user belongs to `gidas-azul`
- AND the HBAC rule for `gidas-azul` permits only `sg-azul` and `pve-desa02`
- WHEN the user attempts SSH to `sg-rojo`
- THEN FreeIPA denies authentication
- AND the SSH session is rejected before a shell is spawned

### S5: AD Domain Controller Failure — Offline Resilience

- GIVEN DC-VM is unreachable (network failure or crash)
- WHEN an existing user (with prior successful login) authenticates to a Linux host
- THEN SSSD serves cached credentials
- AND the user gains access if within the ≥8 h cache window
- AND new users (never authenticated before) cannot log in until AD recovers

### S6: New Subgrupo Creation — Naranja

- GIVEN a new subgrupo "naranja" is approved
- WHEN an admin creates the AD group `gidas-naranja`
- AND creates a FreeIPA HBAC rule permitting access to designated hosts
- AND adds users to `gidas-naranja`
- THEN members can access only the hosts defined in the HBAC rule
- AND members cannot access hosts assigned to other subgrupos

## Acceptance Criteria

| ID  | Criterion | Verification |
|-----|-----------|-------------|
| AC1 | Domain resolvable | `dig SRV _kerberos._tcp.<DOMAIN>` returns AD + FreeIPA records |
| AC2 | Trust established | `ipa trust-find` lists the AD domain |
| AC3 | SSH auth works | `ssh user@linux-host` succeeds with AD credentials |
| AC4 | PVE auth works | Login to PVE web UI succeeds with AD credentials |
| AC5 | HBAC enforced | `gidas-azul` user is rejected when SSH-ing to `sg-rojo` |
| AC6 | Offline auth | SSSD cache allows login ≥8 h after AD disconnection |
| AC7 | Secrets encrypted | `sops -d secrets/proxmox.yaml` reveals AD passwords (no decrypt error) |
| AC8 | LDAPS enabled | `openssl s_client -connect <DC-VM-IP>:636` completes TLS handshake |
| AC9 | Kerberos TTL ≤24 h | `klist -l` shows ticket lifetime ≤24 h |
| AC10 | Backups configured | `ipa-backup --online` succeeds; AD has a scheduled backup job |
| AC11 | Docs exist | `docs/` contains onboarding and offboarding procedures |

## Out of Scope

- ❌ Migration or replacement of DC-VM (unless in critical failure state)
- ❌ Mikrotik router configuration (DNS requirements documented only)
- ❌ External service identity (cloud, email, SaaS)
- ❌ VPN implementation
- ❌ Identity system monitoring (noted as future requirement)
- ❌ Password synchronization between AD and FreeIPA (handled by Kerberos trust)
- ❌ Certificate lifecycle management beyond FreeIPA CA setup
