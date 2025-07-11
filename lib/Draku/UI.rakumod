unit module Draku::UI;

use Terminal::UI 'ui';
use Terminal::ANSI::OO 't';

use Draku::Extract;
use Draku::Render;
use Draku::Search;
use Color::Names;

my $*search-term = Nil;

enum colors is export (
  <yellow limegreen lilac brightturquoise carolinablue>.map:
   { "$_" => '#' ~ Color::Names.color-data("XKCD"){"$_" ~ '-XKCD'}<rgb>.map(*.fmt('%x')).join }
);

sub browse-docs(\pane, :%meta) is export {
 with %meta<file> -> IO::Path $f {
     render-file(pane, $f);
     with %meta<term> -> $term {
       jump-to(pane, $term);
     }
 }

 with %meta<dir> -> IO::Path $d {
   %*dirs-shown{ ~$d } = not %*dirs-shown{ ~$d };
   my $selected = pane.current-line-index;
   pane.clear;
   show-core-docs(pane);
   pane.select($selected);
 }

 with %meta<pod> -> $pod {
   my @opts = links($pod).map: { .<name> => .<target> };
   with ui.select("Choose a link", @opts.map(*.key), @opts.map({.value // .key}), :cancel) -> $chosen {
     with find($chosen) -> $found {
       pane.clear;
       render-file(pane, $found);
       ui.refresh;
     } else {
       ui.alert("couldn't find $chosen");
     }
   }
 }

 with %meta<dist> -> $dist {
   pane.clear;
   my $repo = %meta<repo>;
   pane.put: $dist.meta<name>;
   pane.put: $dist.meta<description>;
   for $dist.meta<provides> -> $p {
     pane.put: $p.raku, wrap => 'hard';
     for $p.keys.sort -> Str $module {
       my $source-file = $repo.source-file( 'sources/' ~ $p{ $module }.values[0]<file> );
       pane.put: $module, meta => %( file => $source-file );
     }
   }
   #for $dist.meta.sort(*<key>) -> (:key($k), :value($v)) {
   #  pane.put: [ $k.fmt('%20s '), $v.raku ], meta => %( $k => $v );
   #}
 }

 with %meta<provides> -> $p {
   pane.clear;
   for $p.sort(*<key>) -> (:key($k), :value($v)) {
     die "no file" without $v.values[0]<file>;
     pane.put: [ $k.fmt('%50s '), $v.raku ], meta => %( file => $v.values[0]<file>.IO );
   }
 }
}

sub find($str) {
  # e.g. /type/IO::Path::QNX  -> $filename
  my @parts = $str.split(/ '::' | '/'/);
  my $found = $*core-docs.child(@parts.join('/') ~ '.pod6' );
  return $found if $found.e;
  return Nil;
}

sub jump-to(\pane, $term) {
  my $n = ui.pane.lines.first( :k, {  .contains($term) } );
  pane.select($n);
}

sub show-core-docs(\pane) is export {
  pane.clear;
  show-dir(pane, core-docs() ); # label => "Core Documentation");
}

sub show-dir(\pane, $dir, :$indent = 5, Str :$label) {
  pane.put: [t.yellow => ($label // $dir.basename).indent($indent - 5)], meta => %(:$dir);
  return unless %*dirs-shown{ $dir.Str }; # TODO
  for $dir.dir.sort -> $entry {
    if $entry.d {
      show-dir(pane, $entry, :indent($indent + 5))
    } else {
      pane.put: $entry.basename.indent($indent), meta => :file($entry)
    }
  }
}

sub show-files(\pane, @files, Str :$term) {
  pane.clear;
  with $term {
    pane.put: [ t.white => "Found ", t.yellow => $term, t.white => " in these places:" ];
  }
  for @files -> $file {
     pane.put: $file.basename, meta => %( :$file, :$term );
  }
}

sub set-actions(\ui,\pane,\nav) is export {
  ui.bind: c => 'show-core-docs';
  ui.bind: 'pane', d => 'debug';

  nav.on: select => {
    with %:meta<repo> -> CompUnit::Repository::Installation $repo {
      pane.clear;
      show-modules-in-repo(pane, :$repo);
    } else {
      with %meta<file> -> IO::Path $f {
        render-file(pane, $f);
        with %meta<line> -> $line { 
          my $text = %meta<text> // '';
          jump-to-term(pane, $line, $text, pod_id => %meta<pod_id>);
        }
      } else {
        show-core-docs(pane);
      }
    }
  }

  nav.on: debug => -> :%meta {
    with %meta<file> -> IO::Path $f {
        $*debug-pod = True;
        render-file(pane, $f);
        $*debug-pod = False;
        with %meta<line> -> $line { 
          my $text = %meta<text> // '';
          jump-to-term(pane, $line, $text);
        }
     } else {
       die "no file in " ~ %meta.raku;
     }
  }

  pane.on: select => { browse-docs(pane, :meta(%:meta)) }
}

sub show-modules-in-repo(\pane,:$repo) is export {
  unless $repo {
    pane.put: "no modules found";
    return;
  }
  for $repo.installed.sort(*.meta<name>) -> $dist {
    pane.put:
      [
        ($dist.meta<name> // '').fmt(' %-25s'),
        ($dist.meta<version> // '').fmt(' %10s'),
        ($dist.meta<auth> // '').fmt(' %-25s'),
      ], meta => %( :$dist, :$repo );
      for $dist.meta<provides>.keys.sort -> $p {
        my %m = $dist.meta<provides>{$p};
        for %m.kv -> $k, $v {
          my $file = $dist.content($k).path;
          pane.put: [ t.yellow => "* $p", t.cyan => " { $k }" ], meta => %( :$file );
        }
      }
  }
}
