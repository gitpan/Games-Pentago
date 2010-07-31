#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Games::Pentago' ) || print "Bail out!
";
}

diag( "Testing Games::Pentago $Games::Pentago::VERSION, Perl $], $^X" );
