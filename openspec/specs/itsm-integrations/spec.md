# itsm-integrations Specification

## Purpose

Integrate GLPI with Redmine and GitLab via REST API — bidirectional event propagation through webhooks and polling.

## Requirements

### Requirement: Change → Redmine

When a Change is created in GLPI, a webhook MUST fire to Redmine creating a corresponding issue with title, description, and GLPI URL.

#### Scenario: Change creates Redmine issue

- GIVEN a Change ticket created in GLPI
- WHEN the webhook fires
- THEN Redmine receives a POST with the change title and body
- AND a new issue is created in the configured Redmine project

#### Scenario: Webhook target unreachable

- GIVEN Redmine is unavailable
- WHEN the webhook fires
- THEN GLPI logs the failure
- AND the webhook retries up to 3 times with exponential backoff

### Requirement: Incident Resolution → GitLab

When an Incident is resolved in GLPI, a notification MUST be sent to GitLab. The system SHOULD add a comment to the linked GitLab issue.

#### Scenario: Resolved incident posts to GitLab

- GIVEN a GitLab issue linked to a GLPI incident
- WHEN the incident status changes to Resolved
- THEN GitLab receives a POST with resolution notes and GLPI URL
- AND a comment is added to the GitLab issue

### Requirement: Secure Credential Storage

API tokens for Redmine and GitLab MUST be stored in a secrets file outside the webroot with restricted permissions (0600).

#### Scenario: Secrets file is protected

- GIVEN a secrets file containing API tokens
- WHEN an auditor checks file permissions
- THEN the file is owned by root:root with mode 0600
- AND it is located outside the GLPI document root
