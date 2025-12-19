unit module Draku::Render;
use Terminal::ANSI::OO 't';
use Color::Scheme;
use Pretty::Table;
use Log::Async;
use Cache::Dir;
use Draku::Conf;

my $*debug-pod;
my $color = Color.new('#54DD30');
my @palette = color-scheme( $color, 'analogous'); #six-tone-ccw');
my $heading = Color.new('#FFFE37');


my $cache = Cache::Dir.new: dir => $cache-dir;

our %COLORS is export is default(t.white) =
  title     => t.color('#ffff00'),
  subtitle  => t.color('#ffff00'),
  heading_1 => t.color(~$heading),
  heading_2 => t.color(~($heading.darken(10))),
  item_1    => t.color(~@palette[3]),
  item_2    => t.color(~( @palette[3].darken(10) ) ),
  code      => t.color(~@palette[2].lighten(30)),
  format_C  => t.color(~@palette[2].lighten(20)),
  format_B  => t.color(~@palette[2].lighten(20)),
  format_I  => t.color(~@palette[2]),
  format_X  => t.color(~@palette[2].lighten(20)),
  text      => t.color(~@palette[3]),
  link      => t.color( ~( @palette[4].lighten(10) ) ),
  error     => t.color('#aabbcc'),
  default   => t.color(~@palette[5]),
;
sub debug-pod(\pane, $pod) is export {
  return unless $*debug-pod;
  pane.put: [ %COLORS<named> => $pod.raku], :wrap<hard>;
}

multi render(\pane, Pod::Block::Named $pod) is export {
  debug-pod(pane, $pod);
  my $contents = join " ", $pod.contents.map: { render($^c, :plain) }
  pane.put: "";
  given $pod.name {
    when 'TITLE' {
      pane.put: [ %COLORS<title> => $contents], :center
    }
    when 'SUBTITLE' {
      pane.put: [ %COLORS<subtitle> => $contents], :center
    }
    default {
      pane.put: [ %COLORS<default> => $contents], :center
    }
  }
}

multi render(\pane, Pod::Block::Para $pod) is export {
  debug-pod(pane, $pod);
  pane.put: "";
  my @pieces = $pod.contents.map: { render($_) }
  pane.put: @pieces, :wrap<hard>, meta => :$pod;
}

multi render( Pod::Block::Para $pod, Bool :$plain) is export {
  $pod.contents.map: { render($_, :$plain) }
}

multi render(\pane, Pod::Heading $pod) is export {
  # level, contents
  my $contents = ( $pod.contents.map: { render($^c, :plain) }).join("\n");
  my $level = $pod.level;
  pane.put: "";
  pane.put: [ %COLORS{"heading_$level"} => ' ' ~ ('─' x (4 - $level)) ~ " $contents " ~ ('─' x (4 - $level)) ],
    meta => %( pod_heading => $level, pod_content => $contents, pod_id => "$level $contents" );
}

multi render(Pod::Heading $pod, Bool :$plain) is export {
  # level, contents
  my $contents = ( $pod.contents.map: { render($^c, :plain) }).join("\n");
  my $level = $pod.level;
  my $text = ' ' ~ ('─' x (4 - $level)) ~ " $contents " ~ ('─' x (4 - $level));
  return $text if $plain;
  %COLORS{"heading_$level"} => $text
}


multi render(\pane, Pod::Item $pod) is export {
  # level, contents
  my $contents = ( $pod.contents.map: { render($^c, :plain) }).join("\n");
  my $level = $pod.level;
  pane.put: [ %COLORS{"item_$level"} => ' ' ~ ('*' x $level) ~ " $contents" ];
}

multi render(\pane, Pod::Block::Code $pod) is export {
  debug-pod(pane, $pod);
  pane.put: "--code start--" if $*debug-pod;
  my $i = 1;
  $pod.contents.map: -> $line {
    last if $i++ == $pod.contents.elems && $line !~~ /\S/;
    next unless $line ~~ /\S/;
    pane.put: [ %COLORS<code> => ($_ // "").indent(4) ] for $line.?lines
  }
  pane.put: "--code end--" if $*debug-pod;
}

sub render-all(\pane, @pod) is export {
  for @pod[0].contents -> $c {
    render(pane, $c);
  }
}

multi render(\pane, Str $pod) is export {
  pane.put: [ %COLORS<text> => $pod], :wrap<hard>;
}

multi render(Str $pod, Bool :$plain) is export {
  return $pod if $plain;
  t.white => $pod
}

multi render(Pod::FormattingCode $pod, Bool :$plain) is export {
  # type, meta
  given $pod.type {
    when 'C' | 'B' | 'I' | 'X' | 'R' | 'E' | 'N' {
      return $pod.contents.map({render($_,:plain)}).join(' ') if $plain;
      %COLORS{ "format_{ $pod.type }" } => $pod.contents.join(' ')
    }
    when 'L' {
      # also has meta
      return $pod.contents.map({render($_, :plain )}) if $plain;
      %COLORS<link> => $pod.contents.map({render($_, :plain )}) 
    }
    default {
      return "unknown : " ~ $pod.raku if $plain;
      t.color('#ffaaaa') => $pod.raku
    }
  }
}

multi render(Pod::Block::Table $pod, Bool :$plain ) is export {
  my $table = Pretty::Table.new;
  if $pod.headers.elems > 0 {
    $table.add-row($pod.headers)
  }
  $pod.contents.map: { $table.add-row($_) }
  $table.gist
}

multi render(\pane, Pod::Block::Table $pod, Bool :$plain ) is export {
  my $table = Pretty::Table.new;
  if $pod.headers.elems > 0 {
    $table.add-row($pod.headers)
  }
  $pod.contents.map: { $table.add-row($_) }
  pane.put: $table.gist
}

multi render(\pane, Pod::FormattingCode $pod) is export {
  debug-pod(pane, $pod);
  pane.put: render($pod);
}

multi render(\pane, $pod) is export {
  pane.put: [ %COLORS<default> => $pod.raku], :wrap<hard>;
}

multi render($pod, Bool :$plain) is export {
  return $pod.raku if $plain;
  t.color('#ff0000') => $pod.raku;
}

sub extract-pod(IO::Path $file) is export {
  $cache.get-cached: $file, {
    my $tmp = $pod-tmp;
    debug "extracting pod from $file";
    shell "raku --doc=Raku $file > $tmp";
    my $in = $tmp.IO.slurp;
    my $pod;
    try {
      $pod = $in.EVAL;
      CATCH {
        default {
          debug "error evaluating pod: $_";
          fail "error evaluating pod: $_";
        }
      }
    }
    $pod;
  }
}

sub render-file(\pane, IO::Path $file, Bool :$debug = so %*ENV<DRAKU_DEBUG>) is export {
  $file.e or die "$file not found";
  pane.clear;
  pane.put: [t.color('#444444') => "rendering $file..."], wrap => 'hard';
  my $pod = try {
    CATCH {
      default {
        pane.put: [t.color('#ffdddd') => "pod errors: $_"] for .Str.lines;
      }
    }
    extract-pod($file);
  }
  unless $pod && $pod[0] {
    pane.put: [t.color('#888444') => "no pod found in $file"];
    for $file.lines -> $line {
      pane.put: $line;
    }
    return;
  }
  for $pod[0].contents -> $c {
    if $debug {
      pane.put: [ $c.^name.fmt('%20s'), '  ', t.color('#777777') => (~render($c.contents[0],:plain)).raku ], meta => %( pod => $c );
    } else {
      #$*debug-pod = True;
      render(pane, $c);
    }
  }
}

sub jump-to-term(\pane, Int $line is copy, Str $text is copy, :$pod_id) is export {
  if $text.starts-with('=') {
    my $pod = try ($text.AST.map: |*.paragraphs).first.Str;
    $text = $pod if $pod;
  }

  with pane.lines.first: :k, { .contains($text) } -> $k {
    pane.select($k);
    return;
  }
  pane.select($line);
}

