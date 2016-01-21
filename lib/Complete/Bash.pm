package Complete::Bash;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
                       point
                       parse_cmdline
                       parse_options
                       format_completion
               );

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Completion module for bash shell',
    links => [
        {url => 'pm:Complete'},
    ],
};

sub _expand_tilde {
    my ($user, $slash) = @_;
    my @ent;
    if (length $user) {
        @ent = getpwnam($user);
    } else {
        @ent = getpwuid($>);
        $user = $ent[0];
    }
    return $ent[7] . $slash if @ent;
    "~$user$slash"; # return as-is when failed
}

sub _add_unquoted {
    no warnings 'uninitialized';

    my ($word, $is_cur_word, $after_ws) = @_;

    #say "D:add_unquoted word=$word is_cur_word=$is_cur_word after_ws=$after_ws";

    $word =~ s!^(~)(\w*)(/|\z) |  # 1) tilde  2) username  3) optional slash
               \\(.)           |  # 4) escaped char
               \$(\w+)            # 5) variable name
              !
                  $1 ? (not($after_ws) || $is_cur_word ? "$1$2$3" : _expand_tilde($2, $3)) :
                      $4 ? $4 :
                          ($is_cur_word ? "\$$5" : $ENV{$5})
                              !egx;
    $word;
}

sub _add_double_quoted {
    no warnings 'uninitialized';

    my ($word, $is_cur_word) = @_;

    $word =~ s!\\(.)           |  # 1) escaped char
               \$(\w+)            # 2) variable name
              !
                  $1 ? $1 :
                      ($is_cur_word ? "\$$2" : $ENV{$2})
                          !egx;
    $word;
}

sub _add_single_quoted {
    my $word = shift;
    $word =~ s/\\(.)/$1/g;
    $word;
}

$SPEC{point} = {
    v => 1.1,
    summary => 'Return line with point marked by a marker',
    description => <<'_',

This is a utility function useful for testing/debugging. `parse_cmdline()`
expects a command-line and a cursor position (`$line`, `$point`). This routine
expects `$line` with a marker character (by default it's the caret, `^`) and
return (`$line`, `$point`) to feed to `parse_cmdline()`.

Example:

    point("^foo") # => ("foo", 0)
    point("fo^o") # => ("foo", 2)

_
    args_as => 'array',
    args => {
        cmdline => {
            summary => 'Command-line which contains a marker character',
            schema => 'str*',
            pos => 0,
        },
        marker => {
            summary => 'Marker character',
            schema => ['str*', len=>1],
            default => '^',
            pos => 1,
        },
    },
    result_naked => 1,
};
sub point {
    my ($line, $marker) = @_;
    $marker //= '^';

    my $point = index($line, $marker);
    die "BUG: No marker '$marker' in line <$line>" unless $point >= 0;
    $line =~ s/\Q$marker\E//;
    ($line, $point);
}

$SPEC{parse_cmdline} = {
    v => 1.1,
    summary => 'Parse shell command-line for processing by completion routines',
    description => <<'_',

This function basically converts COMP_LINE (str) and COMP_POINT (int) into
something like (but not exactly the same as) COMP_WORDS (array) and COMP_CWORD
(int) that bash supplies to shell functions.

The differences with bash are (these differences are mostly for parsing
convenience for programs that use this routine):

1) quotes and backslashes are stripped (bash's COMP_WORDS contains all the
quotes and backslashes);

2) variables are substituted with their values from environment variables except
for the current word (COMP_WORDS[COMP_CWORD]) (bash does not perform variable
substitution for COMP_WORDS). However, note that special shell variables that
are not environment variables like `$0`, `$_`, `$IFS` will not be replaced
correctly because bash does not export those variables for us.

3) tildes (~) are expanded with user's home directory except for the current
word (bash does not perform tilde expansion for COMP_WORDS);

4) no word-breaking characters aside from whitespaces and `=` are currently used
(bash uses COMP_WORDBREAKS which by default also include `:`, `;`, and so on).
This is done for convenience of parsing of Getopt::Long-based applications. More
word-breaking characters might be used in the future, e.g. when we want to
handle complex bash statements like pipes, redirection, etc.

Caveats:

* Due to the way bash parses the command line, the two below are equivalent:

    % cmd --foo=bar
    % cmd --foo = bar

Because they both expand to `['--foo', '=', 'bar']`. But obviously
`Getopt::Long` does not regard the two as equivalent.

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
        opts => {
            summary => 'Options',
            description => <<'_',

Optional. Known options:

* `truncate_current_word` (bool). If set to 1, will truncate current word to the
  position of cursor, for example (`^` marks the position of cursor):
  `--vers^oo` to `--vers` instead of `--versoo`. This is more convenient when
  doing tab completion.

_
            schema => 'hash*',
            pos => 2,
        },
    },
    result => {
        schema => ['array*', len=>2],
        description => <<'_',

Return a 2-element array: `[$words, $cword]`. `$words` is array of str,
equivalent to `COMP_WORDS` provided by bash to shell functions. `$cword` is an
integer, equivalent to `COMP_CWORD` provided by bash to shell functions. The
word to be completed is at `$words->[$cword]`.

Note that COMP_LINE includes the command name. If you want the command-line
arguments only (like in `@ARGV`), you need to strip the first element from
`$words` and reduce `$cword` by 1.


_
    },
    result_naked => 1,
    links => [
    ],
};
sub parse_cmdline {
    no warnings 'uninitialized';
    my ($line, $point, $opts) = @_;

    $line  //= $ENV{COMP_LINE};
    $point //= $ENV{COMP_POINT} // 0;

    die "$0: COMP_LINE not set, make sure this script is run under ".
        "bash completion (e.g. through complete -C)\n" unless defined $line;

    #say "D:line=<$line> point=<$point>";

    my @words;
    my $cword;
    my $pos = 0;
    my $pos_min_ws = 0;
    my $after_ws = 1; # XXX what does this variable mean?
    my $chunk;
    my $add_blank;
    my $is_cur_word;
    $line =~ s!(                                                 # 1) everything
                  (")((?: \\\\|\\"|[^"])*)(?:"|\z)(\s*)       |  # 2) open "  3) content  4) space after
                  (')((?: \\\\|\\'|[^'])*)(?:'|\z)(\s*)       |  # 5) open '  6) content  7) space after
                  ((?: \\\\|\\"|\\'|\\=|\\\s|[^"'=\s])+)(\s*) |  # 8) unquoted word  9) space after
                  = |
                  \s+
              )!
                  $pos += length($1);
                  #say "D: \$1=<$1> \$2=<$3> \$3=<$3> \$4=<$4> \$5=<$5> \$6=<$6> \$7=<$7> \$8=<$8> \$9=<$9>";
                  #say "D:<$1> pos=$pos, point=$point, cword=$cword, after_ws=$after_ws";

                  if ($2 || $5 || defined($8)) {
                      # double-quoted/single-quoted/unquoted chunk

                      if (not(defined $cword)) {
                          $pos_min_ws = $pos - length($2 ? $4 : $5 ? $7 : $9);
                          #say "D:pos_min_ws=$pos_min_ws";
                          if ($point <= $pos_min_ws) {
                              $cword = @words - ($after_ws ? 0 : 1);
                          } elsif ($point < $pos) {
                              $cword = @words + 1 - ($after_ws ? 0 : 1);
                              $add_blank = 1;
                          }
                      }

                      if ($after_ws) {
                          $is_cur_word = defined($cword) && $cword==@words;
                      } else {
                          $is_cur_word = defined($cword) && $cword==@words-1;
                      }
                      #say "D:is_cur_word=$is_cur_word";
                      $chunk =
                          $2 ? _add_double_quoted($3, $is_cur_word) :
                              $5 ? _add_single_quoted($6) :
                              _add_unquoted($8, $is_cur_word, $after_ws);
                      if ($opts && $opts->{truncate_current_word} &&
                              $is_cur_word && $pos > $point) {
                          $chunk = substr(
                              $chunk, 0, length($chunk)-($pos_min_ws-$point));
                          #say "D:truncating current word to <$chunk>";
                      }
                      if ($after_ws) {
                          push @words, $chunk;
                      } else {
                          $words[-1] .= $chunk;
                      }
                      if ($add_blank) {
                          push @words, '';
                          $add_blank = 0;
                      }
                      $after_ws = ($2 ? $4 : $5 ? $7 : $9) ? 1:0;

                  } elsif ($1 eq '=') {
                      # equal sign as word-breaking character
                      push @words, '=';
                      $after_ws = 1;
                  } else {
                      # whitespace
                      $after_ws = 1;
                  }
    !egx;

    $cword //= @words;
    $words[$cword] //= '';

    [\@words, $cword];
}

$SPEC{parse_options} = {
    v => 1.1,
    summary => 'Parse command-line for options and arguments, '.
        'more or less like Getopt::Long',
    description => <<'_',

Parse command-line into words using `parse_cmdline()` then separate options and
arguments. Since this routine does not accept `Getopt::Long` (this routine is
meant to be a generic option parsing of command-lines), it uses a few simple
rules to server the common cases:

* After `--`, the rest of the words are arguments (just like Getopt::Long).

* If we get something like `-abc` (a single dash followed by several letters) it
  is assumed to be a bundle of short options.

* If we get something like `-MData::Dump` (a single dash, followed by a letter,
  followed by some letters *and* non-letters/numbers) it is assumed to be an
  option (`-M`) followed by a value.

* If we get something like `--foo` it is a long option. If the next word is an
  option (starts with a `-`) then it is assumed that this option does not have
  argument. Otherwise, the next word is assumed to be this option's value.

* Otherwise, it is an argument (that is, permute is assumed).

_

    args => {
        cmdline => {
            summary => 'Command-line, defaults to COMP_LINE environment',
            schema => 'str*',
        },
        point => {
            summary => 'Point/position to complete in command-line, '.
                'defaults to COMP_POINT',
            schema => 'int*',
        },
        words => {
            summary => 'Alternative to passing `cmdline` and `point`',
            schema => ['array*', of=>'str*'],
            description => <<'_',

If you already did a `parse_cmdline()`, you can pass the words result (the first
element) here to avoid calling `parse_cmdline()` twice.

_
        },
        cword => {
            summary => 'Alternative to passing `cmdline` and `point`',
            schema => ['array*', of=>'str*'],
            description => <<'_',

If you already did a `parse_cmdline()`, you can pass the cword result (the
second element) here to avoid calling `parse_cmdline()` twice.

_
        },
    },
    result => {
        schema => 'hash*',
    },
};
sub parse_options {
    my %args = @_;

    my ($words, $cword) = @_;
    if ($args{words}) {
        ($words, $cword) = ($args{words}, $args{cword});
    } else {
        ($words, $cword) = @{parse_cmdline($args{cmdline}, $args{point})};
    }

    my @types;
    my %opts;
    my @argv;
    my $type;
    $types[0] = 'command';
    my $i = 1;
    while ($i < @$words) {
        my $word = $words->[$i];
        if ($word eq '--') {
            if ($i == $cword) {
                $types[$i] = 'opt_name';
                $i++; next;
            }
            $types[$i] = 'separator';
            for ($i+1 .. @$words-1) {
                $types[$_] = 'arg,' . @argv;
                push @argv, $words->[$_];
            }
            last;
        } elsif ($word =~ /\A-(\w*)\z/) {
            $types[$i] = 'opt_name';
            for (split '', $1) {
                push @{ $opts{$_} }, undef;
            }
            $i++; next;
        } elsif ($word =~ /\A-([\w?])(.*)/) {
            $types[$i] = 'opt_name';
            # XXX currently not completing option value
            push @{ $opts{$1} }, $2;
            $i++; next;
        } elsif ($word =~ /\A--(\w[\w-]*)\z/) {
            $types[$i] = 'opt_name';
            my $opt = $1;
            $i++;
            if ($i < @$words) {
                if ($words->[$i] eq '=') {
                    $types[$i] = 'separator';
                    $i++;
                }
                if ($words->[$i] =~ /\A-/) {
                    push @{ $opts{$opt} }, undef;
                    next;
                }
                $types[$i] = 'opt_val';
                push @{ $opts{$opt} }, $words->[$i];
                $i++; next;
            }
        } else {
            $types[$i] = 'arg,' . @argv;
            push @argv, $word;
            $i++; next;
        }
    }

    return {
        opts      => \%opts,
        argv      => \@argv,
        cword     => $cword,
        words     => $words,
        word_type => $types[$cword],
        #_types    => \@types,
    };
}

$SPEC{format_completion} = {
    v => 1.1,
    summary => 'Format completion for output (for shell)',
    description => <<'_',

Bash accepts completion reply in the form of one entry per line to STDOUT. Some
characters will need to be escaped. This function helps you do the formatting,
with some options.

This function accepts completion answer structure as described in the `Complete`
POD. Aside from `words`, this function also recognizes these keys:

* `as` (str): Either `string` (the default) or `array` (to return array of lines
  instead of the lines joined together). Returning array is useful if you are
  doing completion inside `Term::ReadLine`, for example, where the library
  expects an array.

* `esc_mode` (str): Escaping mode for entries. Either `default` (most
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
  can use it. For example when you are completing Java or Perl module name (e.g.
  `com.company.product.whatever` or `File::Spec::Unix`) you can use this mode
  (with `path_sep` appropriately set to, e.g. `.` or `::`).

_
    args_as => 'array',
    args => {
        completion => {
            summary => 'Completion answer structure',
            description => <<'_',

Either an array or hash. See function description for more details.

_
            schema=>['any*' => of => ['hash*', 'array*']],
            req=>1,
            pos=>0,
        },
        opts => {
            schema=>'hash*',
            pos=>1,
        },
    },
    result => {
        summary => 'Formatted string (or array, if `as` is set to `array`)',
        schema => ['any*' => of => ['str*', 'array*']],
    },
    result_naked => 1,
};
sub format_completion {
    my ($hcomp, $opts) = @_;

    $opts //= {};

    $hcomp = {words=>$hcomp} unless ref($hcomp) eq 'HASH';
    my $comp     = $hcomp->{words};
    my $as       = $hcomp->{as} // 'string';
    # 'escmode' key is deprecated (Complete 0.11-) and will be removed later
    my $esc_mode = $hcomp->{esc_mode} // $hcomp->{escmode} // 'default';
    my $path_sep = $hcomp->{path_sep};

    if (defined($path_sep) && @$comp == 1) {
        my $re = qr/\Q$path_sep\E\z/;
        my $word;
        if (ref($comp->[0]) eq 'HASH') {
            $comp = [$comp->[0], {word=>"$comp->[0] "}] if
                $comp->[0]{word} =~ $re;
        } else {
            $comp = [$comp->[0], "$comp->[0] "]
                if $comp->[0] =~ $re;
        }
    }

    # XXX this is currently an ad-hoc solution, need to formulate a
    # name/interface for the more generic solution. since bash breaks words
    # differently than us (we only break using '" and whitespace, while bash
    # breaks using characters in $COMP_WORDBREAKS, by default is "'><=;|&(:),
    # this presents a problem we often encounter: if we want to provide with a
    # list of strings containing ':', most often Perl modules/packages, if user
    # types e.g. "Text::AN" and we provide completion ["Text::ANSI"] then bash
    # will change the word at cursor to become "Text::Text::ANSI" since it sees
    # the current word as "AN" and not "Text::AN". the workaround is to chop
    # /^Text::/ from completion answers. btw, we actually chop /^text::/i to
    # handle case-insensitive matching, although this does not have the ability
    # to replace the current word (e.g. if we type 'text::an' then bash can only
    # replace the current word 'an' with 'ANSI). also, we currently only
    # consider ':' since that occurs often.
    if (defined($opts->{word})) {
        if ($opts->{word} =~ s/(.+:)//) {
            my $prefix = $1;
            for (@$comp) {
                if (ref($_) eq 'HASH') {
                    $_->{word} =~ s/\A\Q$prefix\E//i;
                } else {
                    s/\A\Q$prefix\E//i;
                }
            }
        }
    }

    my @res;
    for my $entry (@$comp) {
        my $word = ref($entry) eq 'HASH' ? $entry->{word} : $entry;
        if ($esc_mode eq 'shellvar') {
            # don't escape $
            $word =~ s!([^A-Za-z0-9,+._/\$~-])!\\$1!g;
        } elsif ($esc_mode eq 'none') {
            # no escaping
        } else {
            # default
            $word =~ s!([^A-Za-z0-9,+._/:~-])!\\$1!g;
        }
        push @res, $word;
    }

    if ($as eq 'array') {
        return \@res;
    } else {
        return join("", map {($_, "\n")} @res);
    }
}

1;
#ABSTRACT:

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
 my ($words, $cword) = @{ parse_cmdline() };
 my $res = complete_array_elem(array=>[qw/--help --verbose --version/], word=>$words->[$cword]);
 print format_completion($res);

 % complete -C foo-complete foo
 % foo --v<Tab>
 --verbose --version

This module provides routines for you to be doing the above.


=head1 append:SEE ALSO

Other modules related to bash shell tab completion: L<Bash::Completion>,
L<Getopt::Complete>. L<Term::Bash::Completion::Generator>

Programmable Completion section in Bash manual:
L<https://www.gnu.org/software/bash/manual/html_node/Programmable-Completion.html>
