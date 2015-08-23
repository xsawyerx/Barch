package Barge::Types;
use strict;
use warnings;
use Moose::Util::TypeConstraints;

subtype 'VolumeName',
    as 'Str',
    where   { m/^(\w+|[aA-zZ0-9\-\_\.\+]*)$/ }
    message { "Invalid volume name: $_" };

1;
