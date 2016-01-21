#!perl

use 5.010;
use strict;
use warnings;
#use Log::Any '$log';

use Complete::Bash qw(point parse_cmdline);
use Test::More;

subtest "basic" => sub {
    is_deeply(parse_cmdline(point(q|^aa|)), [['aa'], 0]);
    is_deeply(parse_cmdline(point(q|a^a|)), [['aa'], 0]);
    is_deeply(parse_cmdline(point(q|aa^|)), [['aa'], 0]);
    is_deeply(parse_cmdline(point(q|aa ^|)), [['aa', ''], 1]);
    is_deeply(parse_cmdline(point(q|aa b^|)), [['aa', 'b'], 1]);
    is_deeply(parse_cmdline(point(q|aa b ^|)), [['aa', 'b', ''], 2]);
    is_deeply(parse_cmdline(point(q|aa b c^|)), [['aa', 'b', 'c'], 2]);
};

subtest "whitespace before command" => sub {
    is_deeply(parse_cmdline(point(q|  aa^|)), [['aa'], 0]);
};

subtest "middle" => sub {
    is_deeply(parse_cmdline(point(q|aa b ^c|)), [['aa', 'b', 'c'], 2]);
    is_deeply(parse_cmdline(point(q|aa b ^ c|)), [['aa', 'b', '', 'c'], 2]);
    is_deeply(parse_cmdline(point(q|aa b ^  c|)), [['aa', 'b', '', 'c'], 2]);
};

subtest "escaped space" => sub {
    is_deeply(parse_cmdline(point(q|aa b\\ ^|)), [['aa', 'b '], 1]);
    is_deeply(parse_cmdline(point(q|aa b\\  ^|)), [['aa', 'b ', ''], 2]);
    is_deeply(parse_cmdline(point(q|aa b\\ ^|), '', 1), [['aa', 'b '], 1]);
    is_deeply(parse_cmdline(point(q|aa b\\  ^|), '', 1), [['aa', 'b ', ''], 2]);
};

subtest "double quotes" => sub {
    is_deeply(parse_cmdline(point(q|aa "b c^|)), [['aa', 'b c'], 1]);
    is_deeply(parse_cmdline(point(q|aa "b c ^|)), [['aa', 'b c '], 1]);
    is_deeply(parse_cmdline(point(q|aa "b c'^|)), [['aa', 'b c\''], 1]);
    is_deeply(parse_cmdline(point(q|aa "b c' ^|)), [['aa', 'b c\' '], 1]);
    is_deeply(parse_cmdline(point(q|aa "b c\\"^|)), [['aa', 'b c"'], 1]);
    is_deeply(parse_cmdline(point(q|aa "b c\\" ^|)), [['aa', 'b c" '], 1]);
    is_deeply(parse_cmdline(point(q|aa "b c "^|)), [['aa', 'b c '], 1]);
    is_deeply(parse_cmdline(point(q|aa "b c " ^|)), [['aa', 'b c ', ''], 2]);

    # adjoint with unquoted word (2 adjointed chunks)
    is_deeply(parse_cmdline(point(q|a"b^"|)), [['ab'], 0]);
    is_deeply(parse_cmdline(point(q|a"b"^|)), [['ab'], 0]);
    is_deeply(parse_cmdline(point(q|a"b" ^|)), [['ab', ''], 1]);
    is_deeply(parse_cmdline(point(q|a"b ^"|)), [['ab '], 0]);
    is_deeply(parse_cmdline(point(q|a"b  ^"|)), [['ab  '], 0]);
    is_deeply(parse_cmdline(point(q|a"b "^|)), [['ab '], 0]);
    is_deeply(parse_cmdline(point(q|a"b " ^|)), [['ab ', ''], 1]);

    # adjoint with single-quoted + unquoted (3 adjointed chunks)
    is_deeply(parse_cmdline(point(q|a'c'"b "^|)), [['acb '], 0]);
    is_deeply(parse_cmdline(point(q|a'c'"b " ^|)), [['acb ', ''], 1]);
};

subtest "single quotes" => sub {
    is_deeply(parse_cmdline(point(q|aa 'b c^|)), [['aa', 'b c'], 1]);
    is_deeply(parse_cmdline(point(q|aa 'b c ^|)), [['aa', 'b c '], 1]);
    is_deeply(parse_cmdline(point(q|aa 'b c"^|)), [['aa', 'b c"'], 1]);
    is_deeply(parse_cmdline(point(q|aa 'b c" ^|)), [['aa', 'b c" '], 1]);
    is_deeply(parse_cmdline(point(q|aa \\'b c^|)), [['aa', '\'b', 'c'], 2]);
    is_deeply(parse_cmdline(point(q|aa 'b c '^|)), [['aa', 'b c '], 1]);
    is_deeply(parse_cmdline(point(q|aa 'b c ' ^|)), [['aa', 'b c ', ''], 2]);

    # adjoint with unquoted word
    is_deeply(parse_cmdline(point(q|a'b^'|)), [['ab'], 0]);
    is_deeply(parse_cmdline(point(q|a'b'^|)), [['ab'], 0]);
    is_deeply(parse_cmdline(point(q|a'b' ^|)), [['ab', ''], 1]);
    is_deeply(parse_cmdline(point(q|a'b ^'|)), [['ab '], 0]);
    is_deeply(parse_cmdline(point(q|a'b  ^'|)), [['ab  '], 0]);
    is_deeply(parse_cmdline(point(q|a'b '^|)), [['ab '], 0]);
    is_deeply(parse_cmdline(point(q|a'b ' ^|)), [['ab ', ''], 1]);

    # adjoint with single-quoted + unquoted (3 adjointed chunks)
    is_deeply(parse_cmdline(point(q|a"c"'b '^|)), [['acb '], 0]);
    is_deeply(parse_cmdline(point(q|a"c"'b ' ^|)), [['acb ', ''], 1]);
};

subtest "'=' as word-breaking character" => sub {
    is_deeply(parse_cmdline(point(q|aa --bb^=c|)), [['aa', '--bb', '=', 'c'], 1]);
    is_deeply(parse_cmdline(point(q|aa --bb=c^|)), [['aa', '--bb', '=', 'c'], 3]);

    # escape prevent word breaking
    is_deeply(parse_cmdline(point(q|aa --bb\=c^|)), [['aa', '--bb=c'], 1]);

    # quote protects word break character
    is_deeply(parse_cmdline(point(q|aa "--bb=c"^|)), [['aa', '--bb=c'], 1]);
    is_deeply(parse_cmdline(point(q|aa '--bb=c^|)), [['aa', '--bb=c'], 1]);
};

subtest "variable substitution" => sub {
    local $ENV{var} = "foo";
    local $ENV{var2}; # unknown var

    is_deeply(parse_cmdline(point(q|a^ $var|)), [['a', 'foo'], 0]);
    # not performed on current word
    is_deeply(parse_cmdline(point(q|a $var^|)), [['a', '$var'], 1]);
    is_deeply(parse_cmdline(point(q|a $var^ $var$var|)), [['a', '$var', 'foofoo'], 1]);
    is_deeply(parse_cmdline(point(q|a^ $var2|)), [['a', ''], 0]);

    # escape prevents variable substitution
    is_deeply(parse_cmdline(point(q|a^ \\$var|)), [['a', '$var'], 0]);

    # double quote still allows variable substitution
    is_deeply(parse_cmdline(point(q|a^ "$var|)), [['a', 'foo'], 0]);

    # single quote prevents variable substitution
    is_deeply(parse_cmdline(point(q|a^ '$var|)), [['a', '$var'], 0]);
};

subtest "tilde expansion" => sub {
    my @ent;
    eval { @ent = getpwuid($>) };
    $@ and plan skip_all => 'getpwuid($>) dies (probably not implemented)';
    @ent or plan skip_all => 'getpwuid($>) is empty';

    is_deeply(parse_cmdline(_l(q|a^ ~|)), [['a', "$ent[7]"], 0]);
    is_deeply(parse_cmdline(_l(q|a^ ~/|)), [['a', "$ent[7]/"], 0]);
    is_deeply(parse_cmdline(_l(q|a^ ~/b|)), [['a', "$ent[7]/b"], 0]);
    is_deeply(parse_cmdline(_l(q|a^ ~/~|)), [['a', "$ent[7]/~"], 0]);

    # not an expanded tilde
    is_deeply(parse_cmdline(_l(q|a^ a~|)), [['a', "a~"], 0]);
    is_deeply(parse_cmdline(_l(q|a^ ""~|)), [['a', "~"], 0]);

    # XXX test ~username

    # not performed on current word
    is_deeply(parse_cmdline(_l(q|a ~^|)), [['a', '~'], 1]);

    # escape prevents tilde expansion
    is_deeply(parse_cmdline(_l(q|a^ \\~|)), [['a', '~'], 0]);

    # double quote prevents tilde expansion
    is_deeply(parse_cmdline(_l(q|a^ "~|)), [['a', '~'], 0]);
    # single quote prevents tilde expansion
    is_deeply(parse_cmdline(_l(q|a^ '~|)), [['a', '~'], 0]);
};

subtest "opt:truncate_current_word" => sub {
    is_deeply(parse_cmdline(_l(q|aa^aaa|), {truncate_current_word=>1}),
              [['aa'], 0]);
};

DONE_TESTING:
done_testing;
