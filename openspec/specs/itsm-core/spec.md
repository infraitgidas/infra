# itsm-core Specification

## Purpose

GLPI deployment as the ITSM — incident, change, and problem management with SLA tracking and asset inventory.

## Requirements

### Requirement: Docker Deployment

The system MUST run GLPI via Docker Compose with MariaDB 10.11, nginx reverse proxy with HTTPS termination, and PHP 8.1+.

#### Scenario: Full stack starts cleanly

- GIVEN a fresh LXC with Docker and Compose engine
- WHEN `docker compose up -d` executes
- THEN all containers report healthy status within 120s

#### Scenario: Persistent data survives restart

- GIVEN existing tickets and assets in GLPI
- WHEN the stack restarts
- THEN all data is present without manual recovery

### Requirement: Incident Lifecycle

The system SHALL support the full incident lifecycle: create, assign, work, resolve, close. Transition audit log MUST record actor and timestamp per state change.

#### Scenario: End-to-end incident flow

- GIVEN an authenticated agent user
- WHEN they create, assign, resolve, and close an incident
- THEN the ticket transitions New → Assigned → In Progress → Resolved → Closed
- AND each transition is logged with timestamp and actor

#### Scenario: Unauthenticated request rejected

- GIVEN no valid session
- WHEN a POST to the incident endpoint arrives
- THEN the system returns HTTP 401

### Requirement: CMDB Boundary

Asset inventory MUST cover servers, LXCs, and network services. The system SHALL record a boundary note distinguishing GLPI-managed IT assets from DC infrastructure (NetBox domain).

#### Scenario: Asset created with boundary annotation

- GIVEN an operator with Asset write permission
- WHEN they create an asset with name, type, serial, and location
- THEN the asset appears in the inventory
- AND a note marks it as "GLPI-managed — NetBox is DC source of truth"

### Requirement: RBAC

The system MUST enforce role-based access control via GLPI profiles (Super-Admin, Tech, Observer).

#### Scenario: Observer cannot modify tickets

- GIVEN a user with Observer profile
- WHEN they attempt to edit a ticket
- THEN the system rejects the change and returns a permission error
