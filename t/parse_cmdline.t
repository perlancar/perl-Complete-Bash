#!perl

use 5.010;
use strict;
use warnings;
#use Log::Any '$log';

use Complete::Bash qw(parse_cmdline);
use Test::More;

sub _l {
    my $line = shift;
    my $point = index($line, '^');
    die "BUG: No caret in line <$line>" unless $point >= 0;
    $line =~ s/\^//;
    ($line, $point);
}

subtest "basic" => sub {
    is_deeply(parse_cmdline(_l(q|^aa|)), [['aa'], 0]);
    is_deeply(parse_cmdline(_l(q|a^a|)), [['aa'], 0]);
    is_deeply(parse_cmdline(_l(q|aa^|)), [['aa'], 0]);
    is_deeply(parse_cmdline(_l(q|aa ^|)), [['aa', ''], 1]);
    is_deeply(parse_cmdline(_l(q|aa b^|)), [['aa', 'b'], 1]);
    is_deeply(parse_cmdline(_l(q|aa b ^|)), [['aa', 'b', ''], 2]);
    is_deeply(parse_cmdline(_l(q|aa b c^|)), [['aa', 'b', 'c'], 2]);
};

subtest "whitespace before command" => sub {
    is_deeply(parse_cmdline(_l(q|  aa^|)), [['aa'], 0]);
};

subtest "middle" => sub {
    is_deeply(parse_cmdline(_l(q|aa b ^c|)), [['aa', 'b', 'c'], 2]);
    is_deeply(parse_cmdline(_l(q|aa b ^ c|)), [['aa', 'b', '', 'c'], 2]);
    is_deeply(parse_cmdline(_l(q|aa b ^  c|)), [['aa', 'b', '', 'c'], 2]);
};

subtest "escaped space" => sub {
    is_deeply(parse_cmdline(_l(q|aa b\\ ^|)), [['aa', 'b '], 1]);
    is_deeply(parse_cmdline(_l(q|aa b\\  ^|)), [['aa', 'b ', ''], 2]);
    is_deeply(parse_cmdline(_l(q|aa b\\ ^|), '', 1), [['aa', 'b '], 1]);
    is_deeply(parse_cmdline(_l(q|aa b\\  ^|), '', 1), [['aa', 'b ', ''], 2]);
};

goto DONE_TESTING;

subtest "double quotes" => sub {
    is_deeply(parse_cmdline(_l(q|aa "b c^|)), [['aa', 'b c'], 1]);
    is_deeply(parse_cmdline(_l(q|aa "b c ^|)), [['aa', 'b c '], 1]);
    is_deeply(parse_cmdline(_l(q|aa "b c'^|)), [['aa', 'b c\''], 1]);
    is_deeply(parse_cmdline(_l(q|aa "b c' ^|)), [['aa', 'b c\' '], 1]);
    is_deeply(parse_cmdline(_l(q|aa "b c\\"^|)), [['aa', 'b c"'], 1]);
    is_deeply(parse_cmdline(_l(q|aa "b c\\" ^|)), [['aa', 'b c" '], 1]);
    is_deeply(parse_cmdline(_l(q|aa "b c "^|)), [['aa', 'b c '], 1]);
    is_deeply(parse_cmdline(_l(q|aa "b c " ^|)), [['aa', 'b c ', ''], 2]);

    # adjoint with unquoted word
    is_deeply(parse_cmdline(_l(q|a"b^"|)), [['ab'], 0]);
    is_deeply(parse_cmdline(_l(q|a"b"^|)), [['ab'], 0]);
    is_deeply(parse_cmdline(_l(q|a"b" ^|)), [['ab', ''], 1]);
    is_deeply(parse_cmdline(_l(q|a"b ^"|)), [['ab '], 0]);
    is_deeply(parse_cmdline(_l(q|a"b  ^"|)), [['ab  '], 0]);
    is_deeply(parse_cmdline(_l(q|a"b "^|)), [['ab '], 0]);
    is_deeply(parse_cmdline(_l(q|a"b " ^|)), [['ab ', ''], 1]);
};

subtest "single quotes" => sub {
    is_deeply(parse_cmdline(_l(q|aa 'b c^|)), [['aa', 'b c'], 1]);
    is_deeply(parse_cmdline(_l(q|aa 'b c ^|)), [['aa', 'b c '], 1]);
    is_deeply(parse_cmdline(_l(q|aa 'b c"^|)), [['aa', 'b c"'], 1]);
    is_deeply(parse_cmdline(_l(q|aa 'b c" ^|)), [['aa', 'b c" '], 1]);
    is_deeply(parse_cmdline(_l(q|aa \\'b c^|)), [['aa', '\'b', 'c'], 2]);
    is_deeply(parse_cmdline(_l(q|aa 'b c '^|)), [['aa', 'b c '], 1]);
    is_deeply(parse_cmdline(_l(q|aa 'b c ' ^|)), [['aa', 'b c ', ''], 2]);

    # adjoint with unquoted word
    is_deeply(parse_cmdline(_l(q|a'b^'|)), [['ab'], 0]);
    is_deeply(parse_cmdline(_l(q|a'b'^|)), [['ab'], 0]);
    is_deeply(parse_cmdline(_l(q|a'b' ^|)), [['ab', ''], 1]);
    is_deeply(parse_cmdline(_l(q|a'b ^'|)), [['ab '], 0]);
    is_deeply(parse_cmdline(_l(q|a'b  ^'|)), [['ab  '], 0]);
    is_deeply(parse_cmdline(_l(q|a'b '^|)), [['ab '], 0]);
    is_deeply(parse_cmdline(_l(q|a'b ' ^|)), [['ab ', ''], 1]);
};

subtest "'=' as word-breaking character" => sub {
    is_deeply(parse_cmdline(_l(q|aa --bb^=c|)), [['aa', '--bb', '=', 'c'], 1]);
    is_deeply(parse_cmdline(_l(q|aa --bb=c^|)), [['aa', '--bb', '=', 'c'], 3]);
    # escape prevent word breaking
    is_deeply(parse_cmdline(_l(q|aa --bb\=c^|)), [['aa', '--bb=c'], 1]);
    # quote protects word break character
    is_deeply(parse_cmdline(_l(q|aa "--bb=c"^|)), [['aa', '--bb=c'], 1]);
    is_deeply(parse_cmdline(_l(q|aa '--bb=c^|)), [['aa', '--bb=c'], 1]);
};

DONE_TESTING:
done_testing;
