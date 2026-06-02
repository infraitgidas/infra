# itsm-backup Specification

## Purpose

Automated backup and restore of GLPI persistent data — MariaDB dump and Docker volume snapshots — with proven recovery.

## Requirements

### Requirement: Weekly Database Dump

A MariaDB dump MUST run weekly via cron, producing a compressed SQL file with timestamp outside the Docker volume.

#### Scenario: Backup creates valid dump

- GIVEN a cron trigger for the weekly backup
- WHEN the backup script runs
- THEN a compressed SQL dump is created at /var/backups/glpi/ with ISO timestamp
- AND the exit code is logged

#### Scenario: Backup failure alerts

- GIVEN the database is unreachable
- WHEN the backup script fails
- THEN the script exits non-zero
- AND the failure is logged to syslog

### Requirement: Volume Snapshot

Docker volumes for config, plugins, and documents MUST be snapshotted weekly alongside the database dump.

#### Scenario: Volumes archived atomically

- GIVEN Docker volumes glpi_config, glpi_plugins, glpi_documents
- WHEN the backup script runs
- THEN each volume is archived into a single tarball with the same timestamp as the SQL dump

### Requirement: Restore Procedure

The restore procedure MUST be documented as a shell script and tested at least once before production use.

#### Scenario: Full restore verified

- GIVEN a backup tarball with SQL dump and volume archives
- WHEN the restore script runs on a clean Docker stack
- THEN GLPI starts with all tickets, config, assets, and documents intact

### Requirement: Idempotent Script

The backup script MUST be idempotent — running it multiple times SHALL NOT produce duplicate or corrupted archives.

#### Scenario: Re-run backup safe

- GIVEN a backup exists from the same week
- WHEN the script runs again
- THEN it overwrites the existing archive cleanly
- AND no duplicate files remain
