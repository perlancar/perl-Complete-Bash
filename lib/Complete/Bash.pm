package Complete::Bash;

use 5.010001;
use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
                       parse_cmdline
                       format_completion
               );

# DATE
# VERSION

our %SPEC;

$SPEC{parse_cmdline} = {
    v => 1.1,
    summary => 'Parse shell command-line for processing by completion routines',
    description => <<'_',

Currently only supports bash. This function basically converts COMP_LINE (str)
and COMP_POINT (int) to become COMP_WORDS (array) and COMP_CWORD (int), like
what bash supplies to shell functions. The differences with bash are: 1) quotes
and backslashes are by default stripped, unless you specify `preserve_quotes`;
2) no word-breaking characters aside from whitespaces are used, unless you
specify more word-breaking characters by setting `word_breaks`.

_
    args_as => 'array',
    args => {
        cmdline => {
            summary => 'Command-line, defaults to COMP_LINE environment',
            schema => 'str*',
            pos => 0,
        },
        point => {
            summary => 'Point/position to complete in command-line, '.
                'defaults to COMP_POINT',
            schema => 'int*',
            pos => 1,
        },
        word_breaks => {
            summary => 'Extra characters to break word at',
            description => <<'_',

In addition to space and tab.

Example: `=:`.

Note that the characters won't break words if inside quotes or escaped.

_
            schema => 'str',
            pos => 2,
        },
        preserve_quotes => {
            summary => 'Whether to preserve quotes, like bash does',
            schema => 'bool',
            default => 0,
            pos => 3,
        },
    },
    result => {
        schema => ['array*', len=>2],
        description => <<'_',

Return a 2-element array: `[$words, $cword]`. `$words` is array of str,
equivalent to `COMP_WORDS` provided by bash to shell functions. `$cword` is an
integer, equivalent to `COMP_CWORD` provided by bash to shell functions. The
word to be completed is at `$words->[$cword]`.

_
    },
    result_naked => 1,
};
sub parse_cmdline {
    my ($line, $point, $word_breaks, $preserve_quotes) = @_;

    $line  //= $ENV{COMP_LINE};
    $point //= $ENV{COMP_POINT} // 0;
    $word_breaks //= '';

    die "$0: COMP_LINE not set, make sure this script is run under ".
        "bash completion (e.g. through complete -C)\n" unless defined $line;

    my $pos = 0;
    my $len = length($line);
    # first word is ltrim-ed by bash
    $line =~ s/\A(\s+)//gs and $pos += length($1);

    my @words;
    my $buf;
    my $cword;
    my $escaped;
    my $inserted_empty_word;
    my $double_quoted;
    my $single_quoted;

    my @chars = split //, $line;
    $pos--;
    for my $char (@chars) {
        $pos++;
        #say "D:pos=$pos, char=$char, \@words=[".join(", ", @words)."]";
        if (!defined($cword) && $pos == $point) {
            $cword = @words;
            #say "D:setting cword to $cword";
        }

        if ($escaped) {
            $buf .= $preserve_quotes ? "\\$char" : $char;
            $escaped = undef;
            next;
        }

        if ($char eq '\\') {
            if ($single_quoted) {
                $buf .= $char;
            } else {
                $escaped = 1;
            }
            next;
        }

        if ($char =~ /\s/) {
            if ($single_quoted || $double_quoted) {
                $buf .= $char;
            } else {
                if (defined $buf) {
                    #say "D:pushing word <$buf>";
                    push @words, $buf;
                    undef $buf;
                } elsif (!$inserted_empty_word &&
                             $pos==$point && $chars[$pos-1] =~ /\s/ &&
                                 $pos+1 < $len && $chars[$pos+1] =~ /\s/) {
                    #say "D:insert empty word";
                    push @words, '' unless $words[-1] eq '';
                    $inserted_empty_word++;
                }
            }
            next;
        } else {
            $inserted_empty_word = 0;
        }

        if ($char eq '"') {
            if ($single_quoted) {
                $buf .= $char;
                next;
            }
            $double_quoted = !$double_quoted;
            if (!$double_quoted) {
                $buf .= '"' if $preserve_quotes;
            }
            next;
        }

        if ($char eq "'") {
            if ($double_quoted) {
                $buf .= $char;
                next;
            }
            $single_quoted = !$single_quoted;
            if (!$single_quoted) {
                $buf .= "'" if $preserve_quotes;
            }
            next;
        }

        if (index($word_breaks, $char) >= 0) {
            if ($escaped || $single_quoted || $double_quoted) {
                $buf .= $single_quoted ? "'":'"' if !defined($buf) && $preserve_quotes;
                $buf .= $char;
                next;
            }
            push @words, $buf if defined $buf;
            push @words, $char;
            undef $buf;
            next;
        }

        $buf .= $single_quoted ? "'" : $double_quoted ? '"' : '' if !defined($buf) && $preserve_quotes;
        $buf .= $char;
    }

    if (defined $buf) {
        #say "D:pushing last word <$buf>";
        push @words, $buf;
        $cword //= @words-1;
    } else {
        if (!@words || $words[-1] ne '') {
            $cword //= @words;
            $words[$cword] //= '';
        } else {
            $cword //= @words-1;
        }
    }

    return [\@words, $cword];
}

$SPEC{format_completion} = {
    v => 1.1,
    summary => 'Format completion for output (for shell)',
    description => <<'_',

Bash accepts completion reply in the form of one entry per line to STDOUT. Some
characters will need to be escaped. This function helps you do the formatting,
with some options.

This function accepts an array (the result of a `complete_*` function), _or_ a
hash (which contains the completion array from a `complete_*` function as well
as other metadata for formatting hints). Known keys:

* `completion` (array): The completion array. You can put the result of
  `complete_*` function here.

* `as` (str): Either `string` (the default) or `array` (to return array of lines
  instead of the lines joined together). Returning array is useful if you are
  doing completion inside `Term::ReadLine`, for example, where the library
  expects an array.

* `escmode` (str): Escaping mode for entries. Either `default` (most
  nonalphanumeric characters will be escaped), `shellvar` (like `default`, but
  dollar sign `$` will not be escaped, convenient when completing environment
  variables for example), `filename` (currently equals to `default`), `option`
  (currently equals to `default`), or `none` (no escaping will be done).

* `path_sep` (str): If set, will enable "path mode", useful for
  completing/drilling-down path. Below is the description of "path mode".

  In shell, when completing filename (e.g. `foo`) and there is only a single
  possible completion (e.g. `foo` or `foo.txt`), the shell will display the
  completion in the buffer and automatically add a space so the user can move to
  the next argument. This is also true when completing other values like
  variables or program names.

  However, when completing directory (e.g. `/et` or `Downloads`) and there is
  solely a single completion possible and it is a directory (e.g. `/etc` or
  `Downloads`), the shell automatically adds the path separator character
  instead (`/etc/` or `Downloads/`). The user can press Tab again to complete
  for files/directories inside that directory, and so on. This is obviously more
  convenient compared to when shell adds a space instead.

  The `path_sep` option, when set, will employ a trick to mimic this behaviour.
  The trick is, if you have a completion array of `['foo/']`, it will be changed
  to `['foo/', 'foo/ ']` (the second element is the first element with added
  space at the end) to prevent bash from adding a space automatically.

  Path mode is not restricted to completing filesystem paths. Anything path-like
  can use it. For example when you are completing Java or Perl package name
  (e.g. `com.company.product.whatever` or `File::Spec::Unix`) you can use this
  mode (with `path_sep` appropriately set to, e.g. `.` or `::`). But note that
  in the case of `::` since colon is a word-breaking character in Bash by
  default, when typing you'll need to escape it (e.g. `mpath File\:\:Sp<tab>`)
  or use it inside quotes (e.g. `mpath "File::Sp<tab>`).

_
    args_as => 'array',
    args => {
        shell_completion => {
            summary => 'Result of shell completion',
            description => <<'_',

Either an array or hash. See function description for more details.

_
            schema=>['any*' => of => ['hash*', 'array*']],
            req=>1,
            pos=>0,
        },
    },
    result => {
        summary => 'Formatted string (or array, if `as` is set to `array`)',
        schema => ['any*' => of => ['str*', 'array*']],
    },
    result_naked => 1,
};
sub format_completion {
    my ($hcomp) = @_;

    $hcomp = {completion=>$hcomp} unless ref($hcomp) eq 'HASH';
    my $comp     = $hcomp->{completion};
    my $as       = $hcomp->{as} // 'string';
    my $escmode  = $hcomp->{escmode} // 'default';
    my $path_sep = $hcomp->{path_sep};

    if (defined($path_sep) && @$comp == 1 && $comp->[0] =~ /\Q$path_sep\E\z/) {
        $comp = [$comp->[0], "$comp->[0] "];
    }

    my @lines = @$comp;
    for (@lines) {
        if ($escmode eq 'shellvar') {
            # don't escape $
            s!([^A-Za-z0-9,+._/\$-])!\\$1!g;
        } elsif ($escmode eq 'none') {
            # no escaping
        } else {
            # default
            s!([^A-Za-z0-9,+._/:-])!\\$1!g;
        }
    }

    if ($as eq 'array') {
        return \@lines;
    } else {
        return join("", map {($_, "\n")} @lines);
    }
}

1;
#ABSTRACT: Completion module for bash shell

=head1 DESCRIPTION

Bash allows completion to come from various sources. The simplest is from a list
of words (C<-W>):

 % complete -W "one two three four" somecmd
 % somecmd t<Tab>
 two  three

Another source is from a bash function (C<-F>). The function will receive input
in two variables: C<COMP_WORDS> (array, command-line chopped into words) and
C<COMP_CWORD> (integer, index to the array of words indicating the cursor
position). It must set an array variable C<COMPREPLY> that contains the list of
possible completion:

 % _foo()
 {
   local cur
   COMPREPLY=()
   cur=${COMP_WORDS[COMP_CWORD]}
   COMPREPLY=($( compgen -W '--help --verbose --version' -- $cur ) )
 }
 % complete -F _foo foo
 % foo <Tab>
 --help  --verbose  --version

And yet another source is an external command (including, a Perl script). The
command receives two environment variables: C<COMP_LINE> (string, raw
command-line) and C<COMP_POINT> (integer, cursor location). Program must split
C<COMP_LINE> into words, find the word to be completed, complete that, and
return the list of words one per-line to STDOUT. An example:

 % cat foo-complete
 #!/usr/bin/perl
 use Complete::Bash qw(parse_cmdline format_completion);
 use Complete::Util qw(complete_array_elem);
 my ($words, $cword) = parse_cmdline();
 my $res = complete_array_elem(array=>[qw/--help --verbose --version/], word=>$words->[$cword]);
 print format_completion($res);

 % complete -C foo-complete foo
 % foo --v<Tab>
 --verbose --version

This module provides routines for you to be doing the above.

Instead of being called by bash as an external command every time user presses
Tab, you can also use Perl to I<generate> bash C<complete> scripts for you. See
L<Complete::BashGen>.


=head1 TODOS

format_completion(): Accept regex for path_sep.


=head1 SEE ALSO

L<Complete>

L<Complete::BashGen>

Other modules related to bash shell tab completion: L<Bash::Completion>,
L<Getopt::Complete>. L<Term::Bash::Completion::Generator>

Programmable Completion section in Bash manual:
L<https://www.gnu.org/software/bash/manual/html_node/Programmable-Completion.html>

=cut
