package Barge::Utils;
use strict;
use warnings;

sub convert_time {
    my $time  = shift;
    return "error" if ! $time;

    my $days  = int($time / 86400);
       $time -= ($days * 86400);
    my $hours = int($time / 3600);
       $time -= ($hours * 3600);
    my $minutes = int($time / 60);
    my $seconds = $time % 60;

    $days    = $days    < 1 ? '' : $days  . 'd ';
    $hours   = $hours   < 1 ? '' : $hours . 'h ';
    $minutes = $minutes < 1 ? '' : $minutes.'m ';

    return "$days$hours$minutes${seconds}s";
}
 
sub parse_lvs {
    $_[0] =~ /^\s+(\w+|[aA-zZ0-9\-\_\.\+]*)\s+(\w+)\s+[^ ]+\s+([0-9\.]+)(\w)\s+((\w+|[aA-zZ0-9\-\_\.\+]*)\s+([0-9\.]+))?/;

    return {
        uid      => md5_hex("$2.$1"),
        lvname   => $1,
        vgname   => $2,
        size     => $3,
        unit     => lc($4),
        snapsize => $7,
        origin   => $6,
        blkdev   => "/dev/$2/$1",
        lvsnap   => "${1}$pref"
    };
}

1;
