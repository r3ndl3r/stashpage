#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/lib";
use Mojolicious::Commands;

# Start the application
Mojolicious::Commands->start_app('MyApp');