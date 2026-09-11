# Test server container

An OpenLDAP server preconfigured for the perl-ldap test suite: the same
suffix, manager DN and password `t/common.pl` expects, plus TLS on port
636 using the repository's `data/cert.pem` / `data/key.pem`.

## Build and run

    docker build -t perl-ldap-docker -f contrib/docker/Dockerfile .
    docker run -d -p 389:389 -p 636:636 --rm perl-ldap-docker:latest

    or

    podman build -t perl-ldap-docker -f contrib/docker/Dockerfile .
    podman run -d -p 389:389 -p 636:636 --rm perl-ldap-docker:latest

Run both from the top of the source tree: the build context is the repo
root, so the image can pick up `data/` directly.

(Binding 389/636 needs privileges; map them to unprivileged ports
instead and adjust `$PORT`/`$SSL_PORT` below if you would rather not.)

## Point the test suite at it

Create `my.cfg` in the top of the source tree — it is gitignored and takes
precedence over `test.cfg`:

    $USE_REMOTE_SERVER = 1;
    $SERVER_TYPE = 'openldap+ssl';

    $HOST     = 'localhost';
    $PORT     = 389;
    $SSL_PORT = 636;

    1;

Then run the tests as usual:

    perl Makefile.PL && make && make test

`$CAFILE` defaults to `data/cert.pem`, which is exactly the certificate the
container presents, so TLS certificate verification works out of the box.

## What the image contains

Everything comes from `data/`:

| in the image | from |
| --- | --- |
| `/etc/ldap/data/slapd.conf.in` | `data/slapd.conf.in` |
| `/etc/ldap/data/{cert,key}.pem` | `data/{cert,key}.pem` |
| `/etc/ldap/schema/*.schema` | `data/*.schema` |

Regenerating the test certificate with `data/regenerate_cert.sh` needs no
extra copying - just rebuild the image.

The certificate is self-signed for `CN=localhost`, so connect to the
container as `localhost`; for any other name, set `$SSLSERVER = 'localhost'`
in `my.cfg`.

## Overriding the defaults

`data/slapd.conf.in` is a template: `t/common.pl` fills in its variables
when it starts a local slapd, and `entrypoint.sh` does the same from the
environment, so each one can be set with `-e` at run time.  The defaults
live in `entrypoint.sh` alone - the Dockerfile sets no `ENV` for them, so
there is only one place to change them.

| variable | default |
| --- | --- |
| `BASEDN` | `o=University of Michigan, c=US` |
| `MANAGERDN` | `cn=Manager, o=University of Michigan, c=US` |
| `PASSWD` | `secret` |
| `SLAPD_SCHEMA_DIR` | `/etc/ldap/schema` |
| `SLAPD_DB` | `mdb` |
| `TESTDB` | `/var/lib/ldap` |
| `SERVER_EXE` | `/usr/sbin/slapd` |
| `PORT` | `389` |
| `SSL_PORT` | `636`; `-e SSL_PORT=` serves plain LDAP only |
| `SLAPD_MODULE_DIR` | `/usr/lib/ldap`; leave it set, Debian's slapd loads its backend from there |

For example, to serve a different suffix on unprivileged ports:

    podman run -d -p 9009:9009 -p 9010:9010 --rm \
      -e PORT=9009 -e SSL_PORT=9010 -e BASEDN='o=Example, c=CA' \
      -e MANAGERDN='cn=Manager, o=Example, c=CA' perl-ldap-docker:latest

Set the matching values in `my.cfg` and the test suite will follow.
