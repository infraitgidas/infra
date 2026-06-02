# itsm-ldap-auth Specification

## Purpose

Authenticate GLPI users against FreeIPA LDAP and synchronize user/group membership on a scheduled basis.

## Requirements

### Requirement: LDAP Authentication

The system MUST authenticate users via FreeIPA LDAP bind using a dedicated service account. Admin fallback account MUST bypass LDAP for break-glass access.

#### Scenario: Valid LDAP user logs in

- GIVEN a FreeIPA user jdoe in cn=glpi-users
- WHEN jdoe submits credentials to GLPI
- THEN GLPI binds with the service DN, verifies the password, and grants access
- AND a local GLPI user is auto-provisioned with the correct profile

#### Scenario: Invalid LDAP credentials rejected

- GIVEN a valid FreeIPA user
- WHEN they submit an incorrect password
- THEN GLPI returns a login failure
- AND no local user is created

### Requirement: Scheduled User Sync

The system SHALL synchronize FreeIPA users and groups on a configurable schedule via GLPI's internal LDAP synchronizer or host cron.

#### Scenario: Sync imports new users

- GIVEN a new user added to FreeIPA with memberOf=cn=glpi-users
- WHEN the sync job runs
- THEN the user appears in GLPI with correct group membership

### Requirement: Configurable Connection

LDAP parameters (host, base DN, service account, TLS) MUST be configurable via GLPI setup or config file, not hard-coded.

#### Scenario: Connection parameters updated

- GIVEN an admin changes the LDAP host from ldap1 to ldap2
- WHEN the next LDAP bind occurs
- THEN GLPI connects to ldap2 and authentication succeeds
