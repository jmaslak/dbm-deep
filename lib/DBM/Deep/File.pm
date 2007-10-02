package DBM::Deep::File;

use 5.006_000;

use strict;
use warnings;

our $VERSION = q(1.0006);

use Fcntl qw( :DEFAULT :flock :seek );

sub new {
    my $class = shift;
    my ($args) = @_;

    my $self = bless {
        autobless          => 1,
        autoflush          => 1,
        end                => 0,
        fh                 => undef,
        file               => undef,
        file_offset        => 0,
        locking            => 1,
        locked             => 0,
#XXX Migrate this to the engine, where it really belongs.
        filter_store_key   => undef,
        filter_store_value => undef,
        filter_fetch_key   => undef,
        filter_fetch_value => undef,
    }, $class;

    # Grab the parameters we want to use
    foreach my $param ( keys %$self ) {
        next unless exists $args->{$param};
        $self->{$param} = $args->{$param};
    }

    if ( $self->{fh} && !$self->{file_offset} ) {
        $self->{file_offset} = tell( $self->{fh} );
    }

    $self->open unless $self->{fh};

    return $self;
}

sub open {
    my $self = shift;

    # Adding O_BINARY should remove the need for the binmode below. However,
    # I'm not going to remove it because I don't have the Win32 chops to be
    # absolutely certain everything will be ok.
    my $flags = O_CREAT | O_BINARY;

    if ( !-e $self->{file} || -w _ ) {
      $flags |= O_RDWR;
    }
    else {
      $flags |= O_RDONLY;
    }

    my $fh;
    sysopen( $fh, $self->{file}, $flags )
        or die "DBM::Deep: Cannot sysopen file '$self->{file}': $!\n";
    $self->{fh} = $fh;

    # Even though we use O_BINARY, better be safe than sorry.
    binmode $fh;

    if ($self->{autoflush}) {
        my $old = select $fh;
        $|=1;
        select $old;
    }

    return 1;
}

sub close {
    my $self = shift;

    if ( $self->{fh} ) {
        close $self->{fh};
        $self->{fh} = undef;
    }

    return 1;
}

sub set_inode {
    my $self = shift;

    unless ( defined $self->{inode} ) {
        my @stats = stat($self->{fh});
        $self->{inode} = $stats[1];
        $self->{end} = $stats[7];
    }

    return 1;
}

sub print_at {
    my $self = shift;
    my $loc  = shift;

    local ($/,$\);

    my $fh = $self->{fh};
    if ( defined $loc ) {
        seek( $fh, $loc + $self->{file_offset}, SEEK_SET );
    }

    print( $fh @_ );

    return 1;
}

sub read_at {
    my $self = shift;
    my ($loc, $size) = @_;

    local ($/,$\);

    my $fh = $self->{fh};
    if ( defined $loc ) {
        seek( $fh, $loc + $self->{file_offset}, SEEK_SET );
    }

    my $buffer;
    read( $fh, $buffer, $size);

    return $buffer;
}

sub DESTROY {
    my $self = shift;
    return unless $self;

    $self->close;

    return;
}

sub request_space {
    my $self = shift;
    my ($size) = @_;

    #XXX Do I need to reset $self->{end} here? I need a testcase
    my $loc = $self->{end};
    $self->{end} += $size;

    return $loc;
}

##
# If db locking is set, flock() the db file.  If called multiple
# times before unlock(), then the same number of unlocks() must
# be called before the lock is released.
##
sub lock {
    my $self = shift;
    my ($obj, $type) = @_;

    $type = LOCK_EX unless defined $type;

    if (!defined($self->{fh})) { return; }

    if ($self->{locking}) {
        if (!$self->{locked}) {
            flock($self->{fh}, $type);

            # refresh end counter in case file has changed size
            my @stats = stat($self->{fh});
            $self->{end} = $stats[7];

            # double-check file inode, in case another process
            # has optimize()d our file while we were waiting.
            if (defined($self->{inode}) && $stats[1] != $self->{inode}) {
                $self->close;
                $self->open;

                #XXX This needs work
                $obj->{engine}->setup_fh( $obj );

                flock($self->{fh}, $type); # re-lock

                # This may not be necessary after re-opening
                $self->{end} = (stat($self->{fh}))[7]; # re-end
            }
        }
        $self->{locked}++;

        return 1;
    }

    return;
}

##
# If db locking is set, unlock the db file.  See note in lock()
# regarding calling lock() multiple times.
##
sub unlock {
    my $self = shift;

    if (!defined($self->{fh})) { return; }

    if ($self->{locking} && $self->{locked} > 0) {
        $self->{locked}--;
        if (!$self->{locked}) { flock($self->{fh}, LOCK_UN); }

        return 1;
    }

    return;
}

sub flush {
    my $self = shift;

    # Flush the filehandle
    my $old_fh = select $self->{fh};
    my $old_af = $|; $| = 1; $| = $old_af;
    select $old_fh;

    return 1;
}

1;
__END__
