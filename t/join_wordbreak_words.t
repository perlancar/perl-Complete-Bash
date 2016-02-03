#!perl

use 5.010;
use strict;
use warnings;
#use Log::Any '$log';

use Complete::Bash qw(join_wordbreak_words);
use Test::More;

subtest "basic" => sub {
    is_deeply(
        join_wordbreak_words([qw/cmd --foo = bar -MData :: Dump bob @ example.com > 2/], 9),
        [ [qw/cmd --foo=bar -MData::Dump bob@example.com > 2/], 3 ]
    );
};

DONE_TESTING:
done_testing;
