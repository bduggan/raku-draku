unit module Draku::Search;
use Draku::Conf;

sub search($term, Bool :$all, Int :$max) is export {
  my $file = $term.split('::').join('/') ~ '.pod6';
  my $found = core-docs().dir.first: *.child($file).e;
  $found &&= $found.child($file);
  $found //= $term.IO if $term.IO.e;  # return a list of files
  with $found {
    return ( $found );
  }
  my regex filepath { <-[:]>+ }
  my regex line { <[0..9]>+ }
  my regex text { \V+ }
  my regex grepline { ^^ <filepath> ':' <line> ':' <text> $$ }

  my $base = core-docs();

  my @matches = indir $base, {
    #Q:x:s<<egrep -srnhIH "^=.*$term" .>>
    Q:x:s<<egrep -srnhIH "$term" .>>
      .lines
      .grep: { !m | '/' '.' | }  # no hidden dirs
    ;
  }
  my @results;
  my %file2pod;
  for @matches {
   m/<grepline>/ or note "bad grep line";
   with $<grepline>.Hash {
     #%file2pod{~.<filepath>} //= extract-pod($base.child(.<filepath>).resolve);
     @results.push: %(
       file => $base.child(~.<filepath>).resolve,
       line => +.<line>,
       text => ~.<text>,
       #pod => %file2pod{.<filepath>},
      );
    }
  }

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
