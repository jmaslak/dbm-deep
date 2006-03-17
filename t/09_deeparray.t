##
# DBM::Deep Test
##
use strict;
use Test::More tests => 3;
use File::Temp qw( tempfile tempdir );
use Fcntl qw( :flock );

use_ok( 'DBM::Deep' );

my $dir = tempdir( CLEANUP => 1 );
my ($fh, $filename) = tempfile( 'tmpXXXX', UNLINK => 1, DIR => $dir );
flock $fh, LOCK_UN;

my $max_levels = 1000;

{
    my $db = DBM::Deep->new(
        file => $filename,
        type => DBM::Deep->TYPE_ARRAY,
    );

    $db->[0] = [];
    my $temp_db = $db->[0];
    for my $k ( 0 .. $max_levels ) {
        $temp_db->[$k] = [];
        $temp_db = $temp_db->[$k];
    }
    $temp_db->[0] = "deepvalue";
}

{
    my $db = DBM::Deep->new(
        file => $filename,
        type => DBM::Deep->TYPE_ARRAY,
    );

    my $cur_level = -1;
    my $temp_db = $db->[0];
    for my $k ( 0 .. $max_levels ) {
        $cur_level = $k;
        $temp_db = $temp_db->[$k];
        eval { $temp_db->isa( 'DBM::Deep' ) } or last;
    }
    is( $cur_level, $max_levels, "We read all the way down to level $cur_level" );
    is( $temp_db->[0], "deepvalue", "And we retrieved the value at the bottom of the ocean" );
}
