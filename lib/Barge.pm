package Barge;
use Moose;
use AnyEvent;
use File::Lockfile;
use Barge::Types 'VolumeName';
use Barge::Config;
use Barge::Logger;
use Barge::Utils ();
use namespace::autoclean;

our $VERSION = '6.100';

# Barge::Opts::Duplicyt
# Barge::Opts::DRBD
# Barge::Opts::Global
# Barge::Opts::Advanced
with qw<
    Barge::Commands
>;

has cv => (
    is      => 'ro',
    lazy    => 1,
    default => sub { AE::cv },
);

has configfile => (
    is      => 'ro',
    isa     => 'Str',
    default => sub {'/etc/barch/barch.conf'},
);

has config => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    builder => '_build_config',
);

has only => (
    is        => 'ro',
    isa       => VolumeName,
    predicate => '_has_only',
);

has verbose => (
    is       => 'ro',
    isa      => 'Bool',
    lazy     => 1,
    default  => sub { $_[0]->_has_only || $_[0]->cleanup ? 1 : 0 }, # why?
);

has [ qw<verbose debug graceful dry_run daemon> ] => (
    is      => 'ro',
    isa     => 'Bool',
    default => sub {0},
);

has hostname => (
    is      => 'ro',
    isa     => 'Str',
    default => sub { chomp( my $cmd = `hostname` ); $cmd },
);

has logger => (
    is      => 'ro',
    isa     => 'Barge::Logger',
    lazy    => 1,
    builder => '_build_logger',
);

has drbd_checker => (
    is      => 'ro',
    isa     => 'Barge::Check::DRBD',
    lazy    => 1,
    builder => '_build_drbd_checker',
);

has work_dir => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub { $_[0]->config->{'advanced'}{'work_dir'} },
);

has stop_file => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub { $_[0]->work_dir . '/.graceful' },
);

has facility => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub { $_[0]->config->{'global'}{'facility'} || 'daemon' },
);

has pid_file => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub { $_[0]->config->{'pidfile'} || 'barch.pid' },
);

has lock_dir => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub { $_[0]->config->{'lock_dir'} || '/var/lock/barch' },
);

has lock_file => (
    is      => 'ro',
    isa     => 'File::Lockfile',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return File::Lockfile->new( $self->pid_file, $self->lock_dir );
    },
);

has mount_dir => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub { $_[0]->work_dir . '/mounts' },
);

sub _build_config {
    my $self   = shift;
    my $config = Barge::Config->new( configfile => $self->configfile );
    return $config->read;
}

sub _build_logger {
    my $self = shift;
    return Barge::Logger->new(
        debug        => $self->debug,
        verbose      => $self->verbose,
        log_facility => $self->facility,
    );
}

sub _build_drbd_checker {
    my $self = shift;

    return Barge::Checker::DRBD->new(
        config => $self->config->{'drbd'},
        logger => $self->logger,
    );
}

sub _handle_graceful {
    my $self = shift;

    $self->logger->log(
        'Daemon shutdown scheduled immediately after ' .
        'currently running backups completion'
    );

    $self->run_command( 'touch', $self->stop_file )
         ->then( sub { $self->finish } );
}

sub finish { $_[0]->cv->send }

sub do_cleanup {
    my $self      = shift;
    my $logger    = $self->logger;
    my $mount_dir = $self->mount_dir;

    $mount_dir eq '/'
        or $self->run_command( 'umount', "-r $mount_dir" );

    # remove snapshots
    $self->run_command(
        'lvs', "| grep $pref"
    )->then( sub {
        my @snaps = @_;

        if ( ! @snaps ) {
            $logger->log("No snapshots to remove");
            $self->finish;
        }

        foreach my $snap (@snaps) {
            my $lv_hash = Barge::Utils::parse_lvs($snap);

            # handle snapshots only
            next if( ! $lv_hash->{'snapsize'} && ! $lv_hash->{'origin'} );

            my ( $vgname, $lvname ) = @{$lv_hash}{qw<vgname lvname>};

            # remove partitions, if any
            $self->run_command( 'kpartx', "-s -d /dev/$vgname/$lvname" )
            ->then( sub {
                # umount
                $mount_dir eq '/' or $self->run_command(
                    'umount', "$mount_dir/$lvname"
                );
            })->then( sub {
                if( remove_snapshot("/dev/$vgname/$vname") == 0 ) {
                    $logger->log("$lvname - snapshot removed");
                } else {
                    $logger->log("$lvname - failed to remove snapshot",'Main','err');
                }
            })->then( sub { $self->finish });
        }
    } );
}

sub run {
    my $self = shift;

    $self->graceful
        and $self->_handle_graceful;

    if ( my $pid = $self->lock_file->check ) {
        die "Barch is already running with PID: $pid\n";
    }

    -d $_ or mkdir $_ for $self->lock_dir, $self->mount_dir;

    # mount_dir is created above, so we know we have it
    -d $self->work_dir
        or die "Fatal error. work_dir is undefined.\n";

    $self->cleanup
        and $self->_do_cleanup;

    $self->cv->recv;
}

__PACKAGE__->meta->make_immutable;

1;
