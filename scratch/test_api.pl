#!/usr/bin/env perl
use Mojo::Base -strict;
use Mojo::UserAgent;
use Mojo::JSON qw(decode_json);

my $ua = Mojo::UserAgent->new;
my $url = 'http://localhost:3000/api/v1/dashboard/category/add';

# Since we don't have a session, we expect a 401 or redirect
# But we want to see if it even reaches the logic or fails with a 500
my $tx = $ua->post($url => form => { title => 'TestCat' });

print "Status: " . $tx->res->code . "\n";
print "Body: " . $tx->res->body . "\n";
