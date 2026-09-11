#!perl

use Test::More;

BEGIN { require "t/common.pl" }


start_server()
? plan tests => 7
: plan skip_all => 'no server';

sub sort_results {
    my $results = shift;

    # 1. Open a virtual filehandle to the string
    open my $results_fh, "<", \$results or die $!;

    my $ldif = Net::LDAP::LDIF->new($results_fh, "r") or die $!;
    my @entries;
    while (not $ldif->eof()) {
        push @entries, $ldif->read_entry();
    }
    $ldif->done();
    close $results_fh;
    my @sorted = sort {
        $a->get_value('cn') cmp $b->get_value('cn')
    } @entries;

    my $output_results;
    open my $results_fh, ">", \$output_results or die $!;
    my $out = Net::LDAP::LDIF->new($results_fh, "w", sort => 1);
    foreach my $entry (@sorted) {
        $out->write_entry($entry);
    }
    $out->done();
    close $results_fh;
    $output_results = "version: 1\n" . $output_results;
    return $output_results;
}

SKIP: {
  skip('LWP::UserAgent not installed', 6)
    unless (eval { require LWP::UserAgent });

  $ldap = client();
  ok($ldap, "client");

  $mesg = $ldap->bind($MANAGERDN, password => $PASSWD);

  ok(!$mesg->code, "bind: " . $mesg->code . ": " . $mesg->error);

  ok(ldif_populate($ldap, "data/41-in.ldif"), "data/41-in.ldif");

  my $ua = LWP::UserAgent->new;
  my $res;

# now search the database

  $res = $ua->get("ldap://${HOST}:$PORT/$BASEDN??sub?sn=jensen");
  ok($res->content =~ /2 Matches found/);

  my $expect = <<'LDIF';
version: 1

dn: cn=Barbara Jensen,ou=Information Technology Division,ou=People,o=Universit
 y of Michigan,c=US
objectClass: OpenLDAPperson
cn: Barbara Jensen
cn: Babs Jensen
uid: babs
sn: Jensen
title: Mythical Manager, Research Systems
postalAddress: ITD Prod Dev & Deployment $ 535 W. William St. Room 4212 $ Ann 
 Arbor, MI 48103-4943
seeAlso: cn=All Staff,ou=Groups,o=University of Michigan,c=US
userPassword: bjensen
mail: bjensen@mailgw.umich.edu
homePostalAddress: 123 Wesley $ Ann Arbor, MI 48103
description: Mythical manager of the rsdd unix project
drink: water
homePhone: +1 313 555 2333
pager: +1 313 555 3233
facsimileTelephoneNumber: +1 313 555 2274
telephoneNumber: +1 313 555 9022

dn: cn=Bjorn Jensen,ou=Information Technology Division,ou=People,o=University 
 of Michigan,c=US
objectClass: OpenLDAPperson
cn: Bjorn Jensen
cn: Biiff Jensen
uid: bjorn
sn: Jensen
seeAlso: cn=All Staff,ou=Groups,o=University of Michigan,c=US
userPassword: bjorn
homePostalAddress: 19923 Seven Mile Rd. $ South Lyon, MI 49999
drink: Iced Tea
description: Hiker, biker
title: Director, Embedded Systems
postalAddress: Info Tech Division $ 535 W. William St. $ Ann Arbor, MI 48103
mail: bjorn@mailgw.umich.edu
homePhone: +1 313 555 5444
pager: +1 313 555 4474
facsimileTelephoneNumber: +1 313 555 2177
telephoneNumber: +1 313 555 0355
LDIF

  $res = $ua->get("ldap://${HOST}:$PORT/$BASEDN??sub?(sn=jensen)", Accept => 'text/ldif');
  is(sort_results($res->content),sort_results($expect),'ldif result');

  $res = $ua->get("ldap://${HOST}:$PORT/$BASEDN??sub?(sn=jensen)?x-format=ldif");
  is(sort_results($res->content),sort_results($expect),'ldif result');
}

# Cleanup
ok(ldif_populate($ldap, "data/41-delete.ldif", "delete"), "data/41-delete.ldif");

__END__

# Exact searching
$mesg = $ldap->search(base => $BASEDN, filter => 'sn=jensen');
compare_ldif("41a",$mesg,$mesg->sorted);

# Or searching
$mesg = $ldap->search(base => $BASEDN, filter => '(|(objectclass=groupofnames)(sn=jones))');
compare_ldif("41b",$mesg,$mesg->sorted);

# And searching
$mesg = $ldap->search(base => $BASEDN, filter => '(&(objectclass=groupofnames)(cn=A*))');
compare_ldif("41c",$mesg,$mesg->sorted);

# Not searching
$mesg = $ldap->search(base => $BASEDN, filter => '(!(objectclass=person))');
compare_ldif("41d",$mesg,$mesg->sorted);

