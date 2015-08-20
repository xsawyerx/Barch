package Barch::Check::DRBD;
use Moo;
use AnyEvent;
use AnyEvent::Util 'fork_call';
use XML::Simple;

has config => (
    is       => 'ro',
    required => 1,
);

has drbd_view => (
    is      => 'ro',
    lazy    => 1,
    writer  => 'set_drbd_view',
    default => sub {
        chomp( my @drbd_view = `drbd-overview` );
        return \@drbd_view;
    },
);

has drbd_dump => (
    is      => 'ro',
    lazy    => 1,
    writer  => 'set_drbd_dump',
    default => sub {
        chomp( my $drbd_dump = `drbdadm dump-xml` );
        my $xml = XML::Simple->new();
        return $xml->XMLin($drbd_dump);
    },
);

has watcher => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_watcher',
);

sub _build_watcher {
    my $self   = shift;
    my $config = $self->config;
    my $timer  = $config->{'timer'} || 600;
    my $wdr    = AE::timer $timer, $timer, sub {
        fork_call {
            chomp( my @drbd_view = `drbd-overview`    );
            chomp( my $drbd_dump = `drbdadm dump-xml` );

            return ( \@drbd_view, $drbd_dump );
        } sub {
            @_ == 2 or return;

            my ( $drbd_view, $drbd_dump ) = @_;

            my $xml = XML::Simple->new();
            $self->set_drbd_view($drbd_view);
            $self->set_drbd_dump( $xml->XMLin($drbd_dump) );
        };
    };

    return $wdr;
}

sub check_state {
    my ( $self, $vgname, $lvname ) = @_;
    my $logger    = $self->logger;
    my $drbd_dump = $self->drbd_dump;
    my @drbd_view = @{ $self->drbd_view };
    my $disk      = "/dev/$vgname/$lvname";
    my $drbd_dev  = '';
    my $drbd_disk = '';

    chomp( my $localhost = `hostname` );

    $logger->log("DRBD configuration missing. Cannot identify DRBD device",$lvname,'err')
        if ! $drbd_dump->{'resource'};

    foreach my $resource ( keys %{ $drbd_dump->{'resource'} } ){
        my $k = $drbd_dump->{'resource'}{$resource}{'host'}{$localhost}{'volume'};
        my $d = $k->{'disk'};

        next if not $d;
        
        if( $d eq $disk ){
            $drbd_disk = $d;
            $drbd_dev  = $k->{'device'}{'content'};
            last;
        }
    }
    
    if( $drbd_disk ne '' ){
        my $drbd_name = ( split /\//, $drbd_disk )[-1];

        foreach my $dev ( @drbd_view ){
        $dev =~ /^\s+\d+\:(\w+|[aA-zZ0-9\-\_\.\+]*)\/\d+\s+(\w+)\s+(\w+)\/\w+\s+(\w+)\/.*/;

        last if ! $1;

        if( $1 eq $drbd_name && $2 && $3 && 4 ){
            return {
                dev    => $drbd_dev,
                disk   => $drbd_disk,
                state  => $3,
                conn   => $2,
                status => $4,
            };
        }}
    }

    return {dev => 'undefined'};
}

sub should_do_backup {
    my ( $self, $drbd_data, $lvname ) = @_;
    my $logger      = $self->logger;
    my $drbd_state  = $self->config->{'rbd_state'}   || 'any';
    my $drbd_conn   = $self->config->{'drbd_conn'}   || 'Connected';
    my $drbd_status = $self->config->{'drbd_status'} || 'UpToDate';

    if( $drbd_data->{'dev'} ne 'undefined' ){
        # check DRBD state
        if( lc($drbd_state) ne 'any' &&
            lc($drbd_state) ne lc( $drbd_data->{'state'} )
        ){
            $logger->log("DRBD device state: $drbd_data->{'state'}, skip",
                   $lvname,'warning' );
            return;
        }

        # check DRBD connection
        if( lc($drbd_conn) ne 'any' &&
            lc($drbd_conn) ne lc( $drbd_data->{'conn'} )
        ){
            $logger->log("DRBD device state: $drbd_data->{'conn'}, skip",
                   $lvname, 'warning' );
            return;
        }

        # check DRBD status
        if( lc($drbd_status) ne 'any' &&
            lc($drbd_status) ne lc( $drbd_data->{'status'} )
        ){
            $logger->log("DRBD device state: $drbd_data->{'status'}, skip",
                   $lvname,'warning' );
            return;
        }

        $logger->log("DRBD detected (state: ".$drbd_data->{'state'}.", conn: ".$drbd_data->{'conn'}.", ".
               "status: ".$drbd_data->{'status'}.")", $lvname, 'debug');
    } else {
        $logger->log("No DRBD device found", $lvname, 'debug');
    }

    return 1;
}

sub run {
    my $self = shift;
    $self->drbd_view;
    $self->drbd_dump;
    $self->watcher;
}

1;
