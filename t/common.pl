BEGIN {

  foreach (qw(my.cfg test.cfg)) {
    -f and require "$_" and last;
  }

  undef $SERVER_EXE unless $SERVER_EXE and -x $SERVER_EXE;

  # fallback for the host to connect - needs to support IPv4 & IPv6
  $HOST     ||= 'localhost';
  $HOST6    ||= 'ip6-localhost';
  $PORT     ||= 9009;
  $SSL_PORT ||= 9010
      if grep /^ssl$/i, @server_opts and eval { require IO::Socket::SSL; 1};


  # Where to put temporary files while testing
  # the Makefile is setup to delete temp/ when make clean is run
  $TEMPDIR  = "./temp";
  $SLAPD_SCHEMA_DIR ||= "./data";
  $SLAPD_DB ||= 'mdb';
  $SLAPD_MODULE_DIR ||= '';

  $TESTDB   = "$TEMPDIR/test-db";
  $CONF     = "$TEMPDIR/conf";

  # CA certificate that signed the server's TLS certificate.
  # The bundled test server uses the self-signed data/cert.pem, so that
  # doubles as its own CA.  Set to '' to skip certificate verification.
  $CAFILE   = 'data/cert.pem'  unless defined $CAFILE;
  # Name to check the server certificate against, if it is not $HOST
  # (e.g. when connecting over IPv6 or through a port-forward).
  $SSLSERVER  ||= '';
  $PASSWD   = 'secret';
  $BASEDN   = "o=University of Michigan, c=US";
  $MANAGERDN= "cn=Manager, o=University of Michigan, c=US";
  $JAJDN    = "cn=James A Jones 1, ou=Alumni Association, ou=People, o=University of Michigan, c=US";
  $BABSDN   = "cn=Barbara Jensen, ou=Information Technology Division, ou=People, o=University of Michigan, c=US";
  @URL      = ();

  my @server_opts;
  ($SERVER_TYPE,@server_opts) = split(/\+/, $SERVER_TYPE || 'none');

  if ($SERVER_TYPE =~ /^openldap$/i) {
    $CONF_IN  = "./data/slapd.conf.in";
    $CONF     = "$TEMPDIR/slapd.conf";

    ($IPC_SOCK = "$TEMPDIR/ldapi_sock") =~ s,/,%2f,g
      if grep /^ipc$/i, @server_opts;

    $SASL = 1
      if grep /^sasl$/i, @server_opts and eval { require Authen::SASL; 1 };

    push @URL, "ldap://${HOST}:$PORT/";
    push @URL, "ldap://${HOST6}:$PORT/";
    push @URL, "ldaps://${HOST}:$SSL_PORT/" if $SSL_PORT;
    push @URL, "ldapi://$IPC_SOCK/"         if $IPC_SOCK;
    @LDAPD  = ($SERVER_EXE, '-f', $CONF, '-h', "@URL", qw(-d 1));
  }

  $LDAP_VERSION ||= 3;
  mkdir($TEMPDIR,0777);
  die "$TEMPDIR is not a directory" unless -d $TEMPDIR;
}

use Test::More;
use Net::LDAP;
use Net::LDAP::LDIF;
use Net::LDAP::Util qw(canonical_dn);
use File::Path qw(rmtree);
use File::Basename qw(basename);
use File::Compare qw(compare_text);

my $pid;

sub start_server {
  my %arg = (version => 3, @_);

  return 1 if $USE_REMOTE_SERVER eq '1' && !$arg{ipc};
  return 0
    unless ($LDAP_VERSION >= $arg{version}
	and $LDAPD[0] and -x $LDAPD[0]
	and (!$arg{ssl} or $SSL_PORT)
	and (!$arg{ipc} or $IPC_SOCK));

  if ($CONF_IN and -f $CONF_IN) {
    # Create slapd config file
    open(CONFI, "<$CONF_IN") or die "$!";
    open(CONFO, ">$CONF") or die "$!";
    while(<CONFI>) {
      # this will choke if a variable is not defined
      s/\$([A-Z]\w*)/${$1}/g;

      s/^TLS/#TLS/        unless $SSL_PORT;
      s/^(sasl.*)/#$1/    unless $SASL;
      s/^#module/module/  if $SLAPD_MODULE_DIR;

      print CONFO;
    }
    close(CONFI);
    close(CONFO);
  }

  rmtree($TESTDB) if ( -d $TESTDB );
  mkdir($TESTDB, 0777);
  die "$TESTDB is not a directory" unless -d $TESTDB;

  note("@LDAPD")  if $ENV{TEST_VERBOSE};

  my $log = $TEMPDIR . "/" . basename($0,'.t');

  unless ($pid = fork) {
    die "fork: $!" unless defined $pid;

    open(STDERR, ">$log");
    open(STDOUT, ">&STDERR");
    close(STDIN);

    exec(@LDAPD) or die "cannot exec @LDAPD";
  }

  sleep 2; # wait for server to start
  return 1;
}

sub kill_server {
  if ($pid) {
    kill 9, $pid;
    sleep 2;
    undef $pid;
  }
}

END {
  kill_server();
}

# TLS options needed to talk to the test server, which presents a
# self-signed certificate.  Net::LDAP verifies the peer by default.
sub ssl_opt {
  return (verify => 'none', @_)  unless $CAFILE;
  return (verify => 'require', cafile => $CAFILE,
          $SSLSERVER ? (sslserver => $SSLSERVER) : (), @_);
}

sub client {
  my %arg = @_;
  my $ldap;
  my $count;
  local $^W = 0;
  my %opt = map { $_ => $arg{$_} } grep { exists($arg{$_}) } qw/inet4 inet6 debug/;

  local $HOST = (defined $opt{inet6} && $opt{inet6} eq "1") ? $HOST6 : $HOST;
  if ($arg{ssl}) {
    require Net::LDAPS;
    until($ldap = Net::LDAPS->new($HOST, %opt, ssl_opt(), port => $SSL_PORT, version => 3)) {
      die "ldaps://$HOST:$SSL_PORT/ $@" if ++$count > 10;
      sleep 1;
    }
  }
  elsif ($arg{ipc}) {
    require Net::LDAPI;
    until($ldap = Net::LDAPI->new($IPC_SOCK)) {
      die "ldapi://$IPC_SOCK/ $@" if ++$count > 10;
      sleep 1;
    }
  }
  elsif ($arg{url}) {
    print "Trying $arg{url}\n";
    until($ldap = Net::LDAP->new($arg{url}, %opt, ssl_opt())) {
      die "$arg{url} $@" if ++$count > 10;
      sleep 1;
    }
  }
  else {
    until($ldap = Net::LDAP->new($HOST, %opt, port => $PORT, version => $LDAP_VERSION)) {
      die "ldap://$HOST:$PORT/ $@" if ++$count > 10;
      sleep 1;
    }
  }
  $ldap;
}

sub compare_ldif {
  my($test,$mesg) = splice(@_,0,2);

  unless (ok(!$mesg->code, $mesg->error)) {
    skip($mesg->error, 2);
    return;
  }

  my $ldif = Net::LDAP::LDIF->new("$TEMPDIR/${test}-out.ldif","w", lowercase => 1);
  unless (ok($ldif, "Read ${test}-out.ldif")) {
    skip("Read error", 1);
    return;
  }

  my @canon_opt = (casefold => 'lower', separator => ', ');
  foreach $entry (@_) {
    $entry->dn(canonical_dn($entry->dn, @canon_opt));
    foreach $attr ($entry->attributes) {
      $entry->delete($attr) if $attr =~ /^(modifiersname|modifytimestamp|creatorsname|createtimestamp)$/i;
      if ($attr =~ /^(seealso|member|owner)$/i) {
	$entry->replace($attr => [ map { canonical_dn($_, @canon_opt) } $entry->get_value($attr) ]);
      }
    }
    $ldif->write($entry);
  }

  $ldif->done; # close the file;

  ok(!compare_text("$TEMPDIR/${test}-out.ldif", "data/${test}-cmp.ldif"), "data/${test}-cmp.ldif");
}

sub ldif_populate {
  my ($ldap, $file, $change) = @_;
  my $ok = 1;

  my $ldif = Net::LDAP::LDIF->new($file,"r", changetype => $change || 'add')
	or return;

  while (my $e = $ldif->read_entry) {
    $mesg = $e->update($ldap);
    if ($mesg->code) {
      $ok = 0;
      Net::LDAP::LDIF->new(qw(- w))->write_entry($e);
      print "# ",$mesg->code,": ",$mesg->error,"\n";
    }
  }
  $ok;
}

1;
