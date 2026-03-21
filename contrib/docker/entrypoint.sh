#!/bin/bash
set -e

# 1. Values for the variables in data/slapd.conf.in - the same template
#    t/common.pl fills in when it starts a local slapd.  Defaults match
#    t/common.pl's; override any of them with -e on the run command line.
BASEDN=${BASEDN:-"o=University of Michigan, c=US"}
MANAGERDN=${MANAGERDN:-"cn=Manager, o=University of Michigan, c=US"}
PASSWD=${PASSWD:-"secret"}
SLAPD_SCHEMA_DIR=${SLAPD_SCHEMA_DIR:-/etc/ldap/schema}
SLAPD_DB=${SLAPD_DB:-mdb}
TESTDB=${TESTDB:-/var/lib/ldap}
PORT=${PORT:-389}
SERVER_EXE=${SERVER_EXE:-/usr/sbin/slapd}

#    These two are switches as well as values, so an explicitly empty
#    setting has to survive - hence ${var-default}, not ${var:-default}.
#    -e SSL_PORT= serves plain LDAP only.  -e SLAPD_MODULE_DIR= leaves the
#    module lines commented, as t/common.pl does for a slapd with its
#    backend built in; Debian's slapd loads mdb dynamically and will not
#    start without them, so it is of no use on this image.
SLAPD_MODULE_DIR=${SLAPD_MODULE_DIR-/usr/lib/ldap}
SSL_PORT=${SSL_PORT-636}

# 2. Path Cleanup
mkdir -p "$TESTDB"
chown -R openldap:openldap "$TESTDB" /etc/ldap/data

# 3. Fill in the template.  The patterns use [$] so that the '$' is matched
#    literally rather than as sed's end-of-line anchor.
sed -e "s|[\$]SLAPD_SCHEMA_DIR|${SLAPD_SCHEMA_DIR}|g" \
    -e "s|[\$]SLAPD_MODULE_DIR|${SLAPD_MODULE_DIR}|g" \
    -e "s|[\$]SLAPD_DB|${SLAPD_DB}|g" \
    -e "s|[\$]TESTDB|${TESTDB}|g" \
    -e "s|[\$]BASEDN|${BASEDN}|g" \
    -e "s|[\$]MANAGERDN|${MANAGERDN}|g" \
    -e "s|[\$]PASSWD|${PASSWD}|g" \
    /etc/ldap/data/slapd.conf.in > /etc/ldap/data/slapd.conf

# 4. The same conditional edits t/common.pl makes: enable the module lines
#    when a module directory is configured - Debian's slapd loads its
#    backend dynamically - and drop the TLS settings when there is no
#    LDAPS port to serve.
[ -n "$SLAPD_MODULE_DIR" ] && sed -i -e 's|^#module|module|' /etc/ldap/data/slapd.conf
[ -n "$SSL_PORT" ]         || sed -i -e 's|^TLS|#TLS|'       /etc/ldap/data/slapd.conf

chown openldap:openldap /etc/ldap/data/slapd.conf

# 5. Start slapd on the configured ports
URLS="ldap://0.0.0.0:${PORT}/"
[ -n "$SSL_PORT" ] && URLS="$URLS ldaps://0.0.0.0:${SSL_PORT}/"

exec "$SERVER_EXE" \
    -f /etc/ldap/data/slapd.conf \
    -h "$URLS" \
    -u openldap \
    -g openldap \
    -n localhost \
    -d 1
