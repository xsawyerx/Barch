package Barge::App;
use Moose;
use Barge;
use Getopt::Long qw<:config no_ignore_case>;
use namespace::autoclean;

has barge => (
    is      => 'ro',
    isa     => 'Barge',
    lazy    => 1,
    builder => '_build_barge',
);

our $VERSION = Barge->VERSION;
my  $welcome = sprintf "Barch v%s - LVM Backup Solution\n", Barge->VERSION;

sub _build_barge {
    my $self = shift;
    my $opts = $self->getopt(@ARGV);

    $opts->{'help'} and $self->usage();

    if ( $opts->{'version'} ) {
        print $welcome;
        exit 0;
    }

    my $barge = Barge->new( %{$opts} );

    # replaces "chconfig"
    if ( $opts->{'syntax'} ) {
        # build config, find errors, if any
        $barge->config;
        exit 0;
    };

    return $barge;
}

sub getopt {
    my $self = shift;
    local @ARGV = @_;

    GetOptions(
        \my %opts,
        'verbose|v',
        'version',
        'help|h',
        'cleanup|c',
        'debug',
        'only|o=s',
        'syntax',
        'dry-run',
        'graceful',
        'daemon|d',
    ) || $self->usage('Bad option');

    return \%opts;
}

sub usage {
    print << "_END_USAGE";
$welcome
Copyright (c) 2015 Alexey Baikov <sysboss[\@]mail.ru>

usage: $0 [options] FROM

Options:
  -c|--cleanup             Recovery mode
  -o|--only                Single logical volume to backup
  -h|--help                Help (this info)
  -d|--daemon              Run as a daemon
  --graceful               Graceful stop
  --version                Display version
  --syntax                 Verify config file syntax

Debug Options:
  -v|--verbose             Log to stdout
  --debug                  Debug mode (very verbose)
  --dry-run                Discover only mode

_END_USAGE

    exit 0;
}

sub run { $_[0]->barge->run }

__PACKAGE__->meta->make_immutable;

1;
