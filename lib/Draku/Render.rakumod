unit module Draku::Render;
use experimental :rakuast;
use Terminal::ANSI::OO 't';
use Color;
use Pretty::Table;
use Log::Async;
use Draku::Conf;

my $*debug-pod;
my $nest-depth = 0;
my $heading = Color.new('#FFFE37'); # bright yellow
my $slate   = Color.new('#6A5ACD'); # SlateBlue, base for readable blue text
my $white   = Color.new('#FFFFFF');

our %COLORS is export is default(t.white) =
  title     => t.color(~$heading),
  subtitle  => t.color(~$heading),
  heading_1 => t.color(~$heading),
  heading_2 => t.color(~$heading.darken(10)),
  item_1    => t.color(~$slate.lighten(30)),
  item_2    => t.color(~$slate.lighten(15)),
  code      => t.color(~$white),
  format_C  => t.color(~$white),
  format_B  => t.color(~$heading),
  format_I  => t.color(~$white),
  format_X  => t.color(~$white),
  text      => t.color(~$white),
  link      => t.color('#C77DFF'), # bright violet, analogous to slate blue
  error     => t.color('#aabbcc'),
  default   => t.color(~$white),
;
sub debug-pod(\pane, $pod) is export {
  return unless $*debug-pod;
  pane.put: [ %COLORS<named> => $pod.raku], :wrap<hard>;
}

multi render(\pane, RakuAST::Doc::Paragraph $para) is export {
  debug-pod(pane, $para);
  pane.put: "";
  my @pieces = $para.atoms.map: { render($_) }
  pane.put: @pieces, :wrap<word>, meta => (pod => $para);
}

multi render(RakuAST::Doc::Paragraph $para, Bool :$plain) is export {
  $para.atoms.map: { render($_, :$plain) }
}

sub flatten-plain($x) {
  $x ~~ Iterable ?? $x.map(&flatten-plain).join('') !! $x
}

multi render(\pane, RakuAST::Doc::Block $block) is export {
  given $block.type {
    when 'head' {
      my $level = $block.level.Int;
      my $contents = $block.paragraphs.map({ flatten-plain render($_, :plain) }).join("\n").trim;
      pane.put: "";
      pane.put: [ %COLORS{"heading_$level"} => ' ' ~ ('─' x (4 - $level)) ~ " $contents " ~ ('─' x (4 - $level)) ],
        meta => %( pod_heading => $level, pod_content => $contents, pod_id => "$level $contents" );
    }
    when 'item' {
      my $level = $block.level ?? $block.level.Int !! 1;
      my $contents = $block.paragraphs.map({ flatten-plain render($_, :plain) }).join("\n").trim;
      pane.put: [ %COLORS{"item_$level"} => ' ' ~ ('*' x $level) ~ " $contents" ];
    }
    when 'code' | 'output' | 'implicit-code' {
      debug-pod(pane, $block);
      pane.put: "--code start--" if $*debug-pod;
      my @lines = $block.paragraphs.map({ flatten-plain render($_, :plain) }).join.lines.grep(*.contains(/\S/));
      pane.put: [ %COLORS<code> => $_.indent(4) ] for @lines;
      pane.put: "--code end--" if $*debug-pod;
    }
    when 'pod' {
      $block.paragraphs.map: { render(pane, $_) }
    }
    when 'TITLE' {
      debug-pod(pane, $block);
      my $contents = $block.paragraphs.map({ flatten-plain render($_, :plain) }).join(" ").trim;
      pane.put: "";
      pane.put: [ %COLORS<title> => $contents], :center
    }
    when 'SUBTITLE' {
      debug-pod(pane, $block);
      my $contents = $block.paragraphs.map({ flatten-plain render($_, :plain) }).join(" ").trim;
      pane.put: "";
      pane.put: [ %COLORS<subtitle> => $contents], :center
    }
    when 'DEFN' {
      debug-pod(pane, $block);
      my $contents = $block.paragraphs.map({ flatten-plain render($_, :plain) }).join(" ").trim;
      pane.put: "";
      pane.put: [ %COLORS<default> => $contents ], :wrap<word>;
    }
    when 'table' {
      my $table = Pretty::Table.new(:!header);
      for $block.paragraphs.grep(* ~~ RakuAST::Doc::LegacyRow) -> $row {
        $table.add-row($row.cells.map({ flatten-plain render($_, :plain) }))
      }
      $table.align('l');
      pane.put: $table.gist;
    }
    when 'nested' {
      $nest-depth++;
      LEAVE $nest-depth--;
      render-flow(pane, $block);
    }
    default {
      render-flow(pane, $block);
    }
  }
}

sub render-flow(\pane, RakuAST::Doc::Block $block) {
      debug-pod(pane, $block);
      my $indent = 4 * $nest-depth;
      my @text;
      my sub flush {
        return unless @text;
        for @text.join(" ").split(/\n \s* \n/) -> $para {
          next unless $para.contains(/\S/);
          pane.put: "";
          pane.put: [ %COLORS<default> => $para.subst(/\s+/, ' ', :g).trim], :wrap<word>, :$indent;
        }
        @text = ();
      }
      for $block.paragraphs -> $c {
        if $c ~~ RakuAST::Doc::Block {
          flush;
          render(pane, $c);
        } else {
          @text.push: flatten-plain render($c, :plain);
        }
      }
      flush;
}

multi render(RakuAST::Doc::Block $block, Bool :$plain) is export {
  given $block.type {
    when 'head' {
      my $level = $block.level.Int;
      my $contents = $block.paragraphs.map({ flatten-plain render($_, :plain) }).join("\n").trim;
      my $text = ' ' ~ ('─' x (4 - $level)) ~ " $contents " ~ ('─' x (4 - $level));
      return $text if $plain;
      %COLORS{"heading_$level"} => $text
    }
    when 'item' {
      my $level = $block.level ?? $block.level.Int !! 1;
      my $contents = $block.paragraphs.map({ flatten-plain render($_, :plain) }).join("\n").trim;
      my $text = ' ' ~ ('*' x $level) ~ " $contents";
      return $text if $plain;
      %COLORS{"item_$level"} => $text
    }
    when 'code' | 'output' | 'implicit-code' {
      my @lines = $block.paragraphs.map({ flatten-plain render($_, :plain) }).join.lines.grep(*.contains(/\S/));
      my $text = @lines.map({ $_.indent(4) }).join("\n");
      return $text if $plain;
      %COLORS<code> => $text
    }
    when 'pod' {
      $block.paragraphs.map({ render($_, :plain) }).join("\n")
    }
    when 'TITLE' {
      my $text = $block.paragraphs.map({ flatten-plain render($_, :plain) }).join(" ").trim;
      return $text if $plain;
      %COLORS<title> => $text
    }
    when 'SUBTITLE' {
      my $text = $block.paragraphs.map({ flatten-plain render($_, :plain) }).join(" ").trim;
      return $text if $plain;
      %COLORS<subtitle> => $text
    }
    when 'DEFN' {
      my $text = $block.paragraphs.map({ flatten-plain render($_, :plain) }).join(" ").trim;
      return $text if $plain;
      %COLORS<default> => $text
    }
    when 'table' {
      my $table = Pretty::Table.new(:!header);
      for $block.paragraphs.grep(* ~~ RakuAST::Doc::LegacyRow) -> $row {
        $table.add-row($row.cells.map({ flatten-plain render($_, :plain) }))
      }
      $table.align('l');
      $table.gist
    }
    default {
      my $text = $block.paragraphs.map({ flatten-plain render($_, :plain) }).join("\n").trim;
      return $text if $plain;
      %COLORS<default> => $text
    }
  }
}

multi render(\pane, Str $pod) is export {
  pane.put: [ %COLORS<text> => $pod], :wrap<word>;
}

multi render(Str $pod, Bool :$plain) is export {
  return $pod if $plain;
  %COLORS<text> => $pod
}

multi render(RakuAST::Doc::Markup $markup, Bool :$plain) is export {
  # letter, atoms
  given $markup.letter {
    when 'V' {
      # V<> disarms nested formatting codes: show their literal source text
      my $text = $markup.atoms.map({ $_ ~~ Str ?? $_ !! $_.Str }).join;
      return $text if $plain;
      %COLORS<format_V> => $text
    }
    when 'L' {
      my @parts = $markup.atoms.map: { render($_, :plain) }
      return @parts if $plain;
      %COLORS<link> => @parts
    }
    default {
      my @parts = $markup.atoms.map: { render($_, :plain) }
      return @parts.join(' ') if $plain;
      %COLORS{ "format_{ $markup.letter }" } => @parts.join(' ')
    }
  }
}

multi render(\pane, RakuAST::Doc::Markup $markup) is export {
  debug-pod(pane, $markup);
  pane.put: render($markup);
}

multi render(\pane, $pod) is export {
  pane.put: [ %COLORS<default> => $pod.raku], :wrap<word>;
}

multi render($pod, Bool :$plain) is export {
  return $pod.raku if $plain;
  t.color('#ff0000') => $pod.raku;
}

sub doc-blocks($node, @found) {
  if $node ~~ RakuAST::Doc::Block {
    @found.push: $node;
  } else {
    $node.visit-children: -> $child { doc-blocks($child, @found) };
  }
}

sub extract-pod(IO::Path $file) is export {
  debug "extracting pod from $file";
  my $pod;
  try {
    my @found;
    doc-blocks($file.slurp.AST, @found);
    $pod = @found;
    CATCH {
      default {
        debug "error evaluating pod: $_";
        fail "error evaluating pod: $_";
      }
    }
  }
  $pod;
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
  for $pod[0].paragraphs -> $c {
    if $debug {
      my $label = $c ~~ RakuAST::Doc::Block ?? $c.type !! $c.^name;
      pane.put: [ $label.fmt('%20s'), '  ', t.color('#777777') => (~render($c,:plain)).raku ], meta => %( pod => $c );
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

