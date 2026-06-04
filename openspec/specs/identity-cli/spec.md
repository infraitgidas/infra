# Identity CLI Specification

## Purpose

CLI unificado (`gidas-identity`) para operaciones CRUD sobre AD + FreeIPA desde pve-ad, con gestión de contraseñas, grupos, HBAC y notificaciones por email. Reemplaza la gestión fragmentada vía RSAT/ADUC (Windows) e ipa CLI (FreeIPA).

## Requirements

### R1: User CRUD

The system MUST create, modify, list, show, and delete user accounts across AD and FreeIPA simultaneously.

#### Scenario: Create user — happy path

- GIVEN user "jperez" does not exist in AD nor FreeIPA
- WHEN `gidas-identity user create --name "Juan Pérez" --username jperez --role becario --proyecto Telepark --notify` is executed
- THEN user is created in AD with correct attributes AND in FreeIPA
- AND an email notification is sent with user details

#### Scenario: Create user — duplicate

- GIVEN user "jperez" already exists in AD
- WHEN `gidas-identity user create --username jperez` is executed
- THEN command exits with a clear error message
- AND no changes are made to FreeIPA

#### Scenario: Delete user — confirmation

- GIVEN user "jperez" exists in both systems
- WHEN `gidas-identity user delete --username jperez` is executed
- THEN the system prompts for confirmation before proceeding
- AND user is removed from both systems only after confirmation

#### Scenario: Disable user

- GIVEN user "jperez" exists and is enabled in both systems
- WHEN `gidas-identity user modify --username jperez --disable` is executed
- THEN user account is disabled in AD AND FreeIPA

### R2: Password Management

The system MUST support password reset with force-change-on-next-login for user accounts.

#### Scenario: Reset with force change

- GIVEN user "jperez" exists in both AD and FreeIPA
- WHEN `gidas-identity user password --username jperez --reset --force-change` is executed
- THEN password is reset in AD AND FreeIPA
- AND the user MUST change password at next login in both systems

#### Scenario: Reset — non-existent user

- GIVEN user "nonexistent" does not exist in either system
- WHEN `gidas-identity user password --username nonexistent --reset` is executed
- THEN command exits with error "user not found"
- AND no password changes occur

### R3: Group Membership

The system MUST support add-member, remove-member, and listing of groups across AD and FreeIPA.

#### Scenario: Add member to group

- GIVEN user "jperez" and group "PROY-Telepark" exist in both systems
- WHEN `gidas-identity group add-member --group PROY-Telepark --user jperez` is executed
- THEN jperez is added to PROY-Telepark in AD AND FreeIPA

#### Scenario: Remove member from group

- GIVEN jperez is a member of PROY-Telepark in both systems
- WHEN `gidas-identity group remove-member --group PROY-Telepark --user jperez` is executed
- THEN jperez is removed from PROY-Telepark in AD AND FreeIPA

### R4: HBAC Rules

The system SHOULD support listing and toggling FreeIPA HBAC (Host-Based Access Control) rules.

#### Scenario: List rules for a user

- GIVEN user "jperez" exists in FreeIPA with applicable HBAC rules
- WHEN `gidas-identity hbac list --user jperez` is executed
- THEN enabled and disabled rules applicable to jperez are displayed

#### Scenario: Toggle rule enable

- GIVEN HBAC rule "allow-telepark-ssh" exists in FreeIPA and is currently disabled
- WHEN `gidas-identity hbac toggle --rule allow-telepark-ssh --enable` is executed
- THEN the rule is enabled in FreeIPA

### R5: Email Notifications

The system SHALL send email notifications for user operations when the `--notify` flag is used. SMTP configuration MUST be stored encrypted via SOPS.

#### Scenario: Notify on user create

- GIVEN a valid SMTP configuration exists in encrypted secrets
- WHEN `gidas-identity user create --username jperez --notify` completes successfully
- THEN an email with user details and credentials is sent to the configured recipient

## Acceptance Criteria

| # | Criterion |
|---|-----------|
| AC1 | `gidas-identity user create --username test --notify` creates in AD + FreeIPA, sends email |
| AC2 | `gidas-identity user modify --username test --disable` disables in both systems |
| AC3 | `gidas-identity user password --username test --reset --force-change` resets password in both |
| AC4 | `gidas-identity user delete --username test` requires confirmation before deletion |
| AC5 | `gidas-identity group add-member --group PROY-Telepark --user test` reflects in AD + FreeIPA |
| AC6 | `gidas-identity group remove-member --group PROY-Telepark --user test` removes from both |
| AC7 | `gidas-identity hbac list --user test` displays applicable HBAC rules |
| AC8 | `gidas-identity hbac toggle --rule test-rule --enable` enables the rule in FreeIPA |

## Non-functional Requirements

| # | Requirement | Category |
|---|-------------|----------|
| NF1 | All operations MUST log command, user, timestamp, and outcome. Passwords MUST NEVER appear in logs. | Logging |
| NF2 | WinRM operations MUST retry up to 3 times on timeout or transient failure before reporting error. | Reliability |
| NF3 | Email delivery failure MUST NOT block the CLI operation; failure is logged and CLI exits normally. | Reliability |
| NF4 | The container MUST run as a non-root user. | Security |
| NF5 | Credentials MUST be decrypted from SOPS-encrypted YAML in memory only, and MUST NOT persist in environment variables or temp files. | Security |
| NF6 | Container startup MUST verify SOPS decryption works before accepting commands. | Security |
| NF7 | User CRUD operations SHOULD complete within 30 seconds. | Performance |
| NF8 | Group and HBAC operations SHOULD complete within 10 seconds. | Performance |
