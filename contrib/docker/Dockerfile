FROM docker.io/library/debian:bookworm-slim

# ── System packages ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    slapd ldap-utils perl \
    cpanminus make gcc libc6-dev \
    procps net-tools libssl-dev \
    libnet-ssleay-perl libio-socket-ssl-perl \
    libauthen-sasl-perl ca-certificates vim \
    && rm -rf /var/lib/apt/lists/*

# ── Perl modules ─────────────────────────────────────────────────────────────
RUN cpanm --notest \
    Text::Soundex Net::LDAP Net::LDAP::LDIF \
    Net::LDAP::Util Net::LDAPS Net::LDAPI \
    File::Path File::Basename File::Compare \
    || (cat /root/.cpanm/work/*/build.log && exit 1)

WORKDIR /etc/ldap/

# ── Files and Permissions ────────────────────────────────────────────────────
# Create required directories for the database and schemas
RUN mkdir -p /etc/ldap/data /etc/ldap/schema /var/lib/ldap /etc/ldap/temp/db

# Explicitly copy files to their intended locations.
# The build context is the top of the source tree, so the schemas and the
# TLS certificate come straight from data/ - the same files a locally
# started slapd uses - and there is only one copy of them to maintain.
COPY data/*.schema              /etc/ldap/schema/
COPY data/slapd.conf.in         /etc/ldap/data/
# slapd.conf.in refers to the certificate as ./data/cert.pem, relative to
# the WORKDIR above
COPY data/cert.pem data/key.pem /etc/ldap/data/

# Ensure the slapd user (openldap) can read/write to its directories
RUN chmod 644 /etc/ldap/data/slapd.conf.in && \
    chmod 600 /etc/ldap/data/key.pem && \
    chown -R openldap:openldap /var/lib/ldap /etc/ldap/schema \
    /etc/ldap/data /etc/ldap/temp

EXPOSE 389 636
COPY contrib/docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
CMD ["/entrypoint.sh"]
