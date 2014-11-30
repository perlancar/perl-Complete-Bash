#!perl

use 5.010;
use strict;
use warnings;
#use Log::Any '$log';

use Complete::Bash qw(parse_options);
use Test::More 0.98;

sub _l {
    my $line = shift;
    my $point = index($line, '^');
    die "BUG: No caret in line <$line>" unless $point >= 0;
    $line =~ s/\^//;
    ($line, $point);
}

is_deeply(
    parse_options(cmdline=>q[cmd --help --opt val arg1 arg2 -- --arg3], point=>13),
    {
        argv      => ["arg1", "arg2", "--arg3"],
        cword     => 2,
        options   => { help => [undef], opt => ["val"] },
        word_type => "opt_name",
        words     => ["cmd", "--help", "--opt", "val", "arg1", "arg2", "--", "--arg3"],
    },
);

is_deeply(
    parse_options(cmdline=>q[cmd -abc -MData::Dump], point=>1),
    {
        argv      => [],
        cword     => 0,
        options   => { a => [undef], b => [undef], c => [undef] },
        word_type => "command",
        words     => ["cmd", "-abc", "-MData::Dump"],
    },
);

DONE_TESTING:
done_testing;
