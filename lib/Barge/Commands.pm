package Barge::Commands;
use Carp;
use Moose::Role;
use AnyEvent::Util 'fork_call';
use Promises 'deferred';

has available_commands => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { [ qw<
        lvm lvs vgs rm ssh mount umount file kpartx
        duplicity nice ionice gpg parted touch mkdir
    > ] },
);

has commands => (
    is      => 'ro',
    isa     => 'HashRef[Str]',
    lazy    => 1,
    builder => '_build_commands',
);

has silent => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub { $_[0]->debug ? '' : ' 1>/dev/null 2>/dev/null' },
);

sub _build_commands {
    my $self = shift;

    return [ map {;
        chomp( my $location = `which $_` );

        $location
            or die "[ERR] No $_ found\n";

        $_ => $location;
    } @{ $self->available_commands } ];
}

sub BUILD {
    my $self = shift;
    $self->commands;
}

sub run_command {
    my ( $self, $command, $args ) = @_;

    my $path = $self->tools->{$command}
        or croak "[ERR] Command $command does not exist\n";

    my $promise = deferred;
    my $silent  = $self->silent;
    fork_call {
        chomp( my @content = `$path $args $silent` );
        return \@content;
    } sub {
        $promise->resolve( @{ $_[0] } );
    };

    return $promise;
}

1;
