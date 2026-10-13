unit module Draku::Search;
use Draku::Conf;

my regex filepath { <-[:]>+ }
my regex line { <[0..9]>+ }
my regex text { \V+ }
my regex grepline { ^^ <filepath> ':' <line> ':' <text> $$ }

# Turn egrep -rH output into results: parse path:line:text,
# skip hidden directories, resolve against $base.
sub grep-results($base, @matches, :&filter = { %() }) {
  my @results;
  for @matches {
    m/<grepline>/ or next;  # skip lines we can't parse
    with $<grepline>.Hash {
      my $filepath = ~.<filepath>;
      $filepath.=subst: / ^^ './' /, '';
      next if $filepath.starts-with('.') or $filepath.contains('/.');  # no hidden dirs
      with &filter(~.<text>) -> $extra {
        @results.push: %(
          file => $base.child($filepath).resolve,
          line => +.<line>,
          text => ~.<text>,
          |$extra
         );
      }
    }
  }
  @results
}

sub search($term, Bool :$all, Int :$max) is export {
  my $base = core-docs();
  my $prefix = $term.split('::').join('/');
  my $found;
  for '.rakudoc', '.pod6' -> $ext {
    my $file = $prefix ~ $ext;
    with $base.dir.first: *.child($file).e {
      $found = .child($file);
      last;
    }
  }
  $found //= $term.IO if $term.IO.e;  # return a list of files
  with $found {
    return ( $found );
  }

  my @matches = indir $base, {
    #Q:x:s<<egrep -srnIH "^=.*$term" .>>
    Q:x:s<<egrep -srnIH "$term" .>>
      .lines
    ;
  }
  my @results = grep-results($base, @matches);

  return @results.sort( { [~.<file>, +.<line> ] } ).head($max);
}

# Find declarations of a routine/method/sub/operator etc. by name,
# e.g. search-routine('trans') matches "=head2 method trans".
my @routine-kinds = <routine method sub operator term infix prefix postfix
  circumfix postcircumfix regex token rule trait statement>;
my token routine-kind { @routine-kinds }

sub search-routine($term, Int :$max = 100) is export {
  my $base = core-docs();
  my $needle = '^=head[0-9]+ (' ~ @routine-kinds.join('|') ~ ') ' ~ $term ~ '( |$)';
  my @matches = indir $base, {
    Q:x:s<<egrep -rnIH "$needle" .>>
      .lines
    ;
  }
  my @results = grep-results($base, @matches, filter => -> $text {
    $text ~~ / ^^ '=head' \d+ \h+ $<kind> = <routine-kind> \h+ $<name> = ($term) <?before \h | $$> /
      ?? %( kind => ~$<kind> )
      !! Nil
  });

  return @results.sort( { [~.<file>, +.<line> ] } ).head($max);
}

sub core-docs(Bool :$update) is export {
  mkdir $cache-dir unless $cache-dir.d;
  unless $cache-dir.child('doc').d {
    prompt "core docs not found, press return to clone into $cache-dir >";
    indir $cache-dir, {
      shell "git clone -o github https://github.com/raku/doc.git";
    }
  }
  if $update {
    indir $cache-dir.child('doc'), {
      shell "git pull github";
    }
  }
  $cache-dir.child('doc/doc');
}
