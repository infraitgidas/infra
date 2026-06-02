<?php
// ================================================================
// ldap-auth.php — GLPI LDAP Authentication Configuration
// ================================================================
// Template for configuring GLPI to authenticate against FreeIPA.
//
// This file documents the values to enter in GLPI's LDAP directory
// configuration (Configuration > Authentication > LDAP).
//
// Alternatively, configure via CLI:
//   docker exec glpi-app php bin/console glpi:ldap:add \
//     --name="FreeIPA - Gidas" \
//     --host="ipa.gidas.local" \
//     --port=636 \
//     --basedn="cn=users,cn=accounts,dc=gidas,dc=local" \
//     --rootdn="cn=glpi-svc,cn=sysaccounts,cn=etc,dc=gidas,dc=local" \
//     --use-tls=1 \
//     --rootdn-passwd="<service-account-password>"
// ================================================================

return [
    'name'              => 'FreeIPA - Gidas',

    // --- Connection ---
    'host'              => getenv('LDAP_HOST') ?: 'ipa.gidas.local',
    'port'              => (int)(getenv('LDAP_PORT') ?: 636),
    'basedn'            => getenv('LDAP_BASE_DN') ?: 'cn=users,cn=accounts,dc=gidas,dc=local',

    // --- Service Account ---
    'rootdn'            => getenv('LDAP_BIND_DN') ?: 'cn=glpi-svc,cn=sysaccounts,cn=etc,dc=gidas,dc=local',
    'rootdn_passwd'     => getenv('LDAP_BIND_PASS') ?: '',

    // --- TLS ---
    'use_tls'           => (bool)(getenv('LDAP_TLS') ?: true),
    'tls_cacertfile'    => '/etc/ssl/certs/ca-certificates.crt',
    'tls_checkcrl'      => 0,

    // --- User Search ---
    'user_filter'       => getenv('LDAP_USER_FILTER') ?:
        '(&(objectClass=person)(memberOf=cn=glpi-users,cn=groups,cn=accounts,dc=gidas,dc=local))',
    'user_fields'       => [
        'email'         => 'mail',
        'realname'      => 'sn',
        'firstname'     => 'givenName',
        'phone'         => 'telephoneNumber',
        'mobile'        => 'mobile',
        'title'         => 'title',
        'language'      => 'preferredLanguage',
        'employee_type' => 'employeeType',
    ],

    // --- Group Search ---
    'group_filter'      => '(objectClass=groupOfNames)',
    'group_fields'      => [
        'email'         => 'mail',
        'description'   => 'description',
    ],

    // --- Sync Options ---
    'sync_interval'     => 3600,          // Seconds between syncs
    'sync_import_users' => true,           // Auto-create users from LDAP
    'sync_import_groups' => true,          // Auto-create groups from LDAP
    'sync_delete_users' => false,          // Do NOT delete users removed from LDAP

    // --- Profile Mapping ---
    // Map FreeIPA groups to GLPI profiles:
    //   cn=glpi-admin  → Super-Admin (profile_id: 4)
    //   cn=glpi-tech   → Technician  (profile_id: 6)
    //   cn=glpi-users  → Observer    (profile_id: 7)
    'profile_mapping'   => [
        'cn=glpi-admin,cn=groups,cn=accounts,dc=gidas,dc=local' => 4,
        'cn=glpi-tech,cn=groups,cn=accounts,dc=gidas,dc=local'  => 6,
        'cn=glpi-users,cn=groups,cn=accounts,dc=gidas,dc=local' => 7,
    ],

    // --- Authentication ---
    'auth_method'       => 'ldap',         // ldap (bind) or password (compare)
    'auth_use_dn'       => true,           // Use full DN for bind
    'auth_fallback'     => true,           // Fall back to local auth if LDAP is down

    // --- Debug ---
    'debug'             => (bool)(getenv('LDAP_DEBUG') ?: false),
];
