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

#| Render a list of Pod content items (Str / Pod::FormattingCode / ...) into
#| a list of pieces suitable for pane.put(:wrap<word>). Pane's word-wrap
#| inserts a single space between every piece, so text that is directly
#| glued to the previous item in the source (eg. trailing punctuation right
#| after a L<> or C<> code, with no intervening whitespace) is folded onto
#| the end of the previous piece instead of becoming its own space-padded
#| piece.
sub render-glued-pieces(@contents) is export {
  my @pieces;
  for @contents -> $item {
    my $piece = render($item);
    my $color = $piece ~~ Pair ?? $piece.key !! Nil;
    my $text  = ($piece ~~ Pair ?? $piece.value !! $piece).Str;
    next if $text eq '';
    if $item ~~ Str && $text !~~ /^^ \s/ && @pieces {
      if $text ~~ /^ (<-[\s]>+) (.*)$/ {
        my ($lead, $rest) = (~$0, ~$1);
        my $prev = @pieces[*-1];
        @pieces[*-1] = $prev ~~ Pair ?? ($prev.key => $prev.value ~ $lead) !! ($prev ~ $lead);
        $text = $rest;
      }
    }
    next if $text eq '';
    @pieces.push: $color.defined ?? ($color => $text) !! $text;
  }
  @pieces;
}

multi render(\pane, Pod::Block::Para $pod) is export {
  debug-pod(pane, $pod);
  pane.put: "";
  my @pieces = render-glued-pieces($pod.contents);
  pane.put: @pieces, :wrap<word>, meta => :$pod;
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

sub strip-formatting-codes(Str $s) is export {
  $s.subst: /<[A..Z]> '<' (.*?) '>'/, -> $/ { ~$0 }, :g
}

#| Rakudo's Pod grammar does not parse inline formatting codes (C<>, B<>,
#| L<>, etc.) within =defn bodies -- they arrive as raw, unparsed text.
#| This does a small, single-pass reparse of that text into colored pieces
#| suitable for pane.put(:wrap<word>), recursing one level to handle labels
#| like L<C<=code>|#Code blocks>.
sub inline-pod-pieces(Str $text --> List) is export {
  my @pieces;
  # Glue plain text directly onto the previous piece when the source had no
  # whitespace at the boundary (eg. the "begin" left behind right after a
  # zero-width Z<> code, as in "=Z<>begin code"), instead of letting a new,
  # separately-spaced piece form -- mirrors render-glued-pieces.
  my sub push-plain(Str $s is copy) {
    return unless $s.chars;
    while @pieces && $s !~~ /^^ \s/ && $s ~~ /^ (<-[\s]>+) (.*)$/ {
      my ($lead, $rest) = (~$0, ~$1);
      my $prev = @pieces[*-1];
      @pieces[*-1] = $prev ~~ Pair ?? ($prev.key => $prev.value ~ $lead) !! ($prev ~ $lead);
      $s = $rest;
    }
    @pieces.push: $s if $s.chars;
  }
  my $buf = '';
  my $pos = 0;
  my $len = $text.chars;
  while $pos < $len {
    my $ch = $text.substr($pos, 1);
    if $ch ~~ /<[A..Z]>/ && $pos + 1 < $len && $text.substr($pos + 1, 1) eq '<' {
      my $start = $pos + 2;
      my $i = $start;
      my $depth = 1;
      while $i < $len && $depth > 0 {
        given $text.substr($i, 1) {
          when '<' { $depth++ }
          when '>' { $depth-- }
        }
        $i++;
      }
      if $depth == 0 {
        my $inner = $text.substr($start, $i - $start - 1);
        push-plain($buf); $buf = '';
        given $ch {
          when 'L' {
            my ($label, $target) = $inner.split('|', 2);
            my $label-text = inline-pod-pieces($label // $target).map({ $_ ~~ Pair ?? $_.value !! $_ }).join('');
            @pieces.push: %COLORS<link> => $label-text if $label-text.chars;
          }
          when 'C' | 'B' | 'I' | 'R' | 'X' | 'E' | 'N' {
            my $outer-color = %COLORS{"format_$ch"};
            @pieces.push: |inline-pod-pieces($inner).map({ $_ ~~ Pair ?? $_ !! ($outer-color => $_) });
          }
          default {
            push-plain($inner);
          }
        }
        $pos = $i;
        next;
      }
    }
    $buf ~= $ch;
    $pos++;
  }
  push-plain($buf);
  @pieces;
}

#| Reparses raw =defn body text (see inline-pod-pieces) into display lines.
#| Each line is either `marker => Str` for a literal "=begin NAME" / "=end
#| NAME" token, or a List of pieces for ordinary word-wrapped prose/code
#| spans. Marker detection only runs over plain-text stretches -- text
#| inside a formatting code escape (eg. the deliberately-literal
#| B<=begin code :nested(0)>, used to show =begin/=end syntax without
#| triggering it) is treated as opaque and never split, so escaped example
#| syntax stays on one line instead of being torn apart. Original line
#| breaks within these examples are already lost upstream (Rakudo doesn't
#| parse nested delimited blocks inside =defn), so this can only isolate
#| the markers, not restore layout.
sub defn-body-lines(Str $text --> List) is export {
  my @lines;
  my @pieces;
  my $buf = '';

  my sub flush-pieces {
    @lines.push: @pieces.List if @pieces;
    @pieces = ();
  }
  my sub push-plain-piece(Str $s is copy) {
    return unless $s.chars;
    while @pieces && $s !~~ /^^ \s/ && $s ~~ /^ (<-[\s]>+) (.*)$/ {
      my ($lead, $rest) = (~$0, ~$1);
      my $prev = @pieces[*-1];
      @pieces[*-1] = $prev ~~ Pair ?? ($prev.key => $prev.value ~ $lead) !! ($prev ~ $lead);
      $s = $rest;
    }
    @pieces.push: $s if $s.chars;
  }
  my sub flush-buf {
    return unless $buf.chars;
    # A marker also swallows any trailing :config<...> options (eg. the
    # :allow<B V> on "=begin code :allow<B V>") so they don't leak out as
    # visible prose on the following line -- only the bare "=begin NAME" /
    # "=end NAME" head is kept for display.
    for $buf.split(
      / $<head>=('=' ['begin' | 'end'] \s+ \S+)
        [ \s+ ':' '!'? \w+ [ '<' <-[<>]>* '>' | '(' <-[()]>* ')' | '{' <-[{}]>* '}' ]? ]* /,
      :v
    ) -> $part {
      if $part ~~ Match {
        flush-pieces;
        @lines.push: (marker => $part<head>.Str);
      } else {
        push-plain-piece($part.Str);
      }
    }
    $buf = '';
  }
  my sub push-code-piece($color, Str $text) {
    return unless $text.chars;
    flush-buf;
    @pieces.push: $color.defined ?? ($color => $text) !! $text;
  }
  #| Recursively reparse a formatting code's inner text for further nested
  #| codes (eg. the I<> inside B<I< Warning ... >>), instead of dumping it
  #| as one opaque, uncolored, unstripped blob. Plain stretches take the
  #| outer color; a nested code's own color wins over it.
  my sub push-nested-code-piece($outer-color, Str $text) {
    return unless $text.chars;
    flush-buf;
    for inline-pod-pieces($text) -> $ip {
      @pieces.push: $ip ~~ Pair ?? $ip !! ($outer-color.defined ?? ($outer-color => $ip) !! $ip);
    }
  }

  my $pos = 0;
  my $len = $text.chars;
  while $pos < $len {
    my $ch = $text.substr($pos, 1);
    if $ch ~~ /<[A..Z]>/ && $pos + 1 < $len && $text.substr($pos + 1, 1) eq '<' {
      my $start = $pos + 2;
      my $i = $start;
      my $depth = 1;
      while $i < $len && $depth > 0 {
        given $text.substr($i, 1) {
          when '<' { $depth++ }
          when '>' { $depth-- }
        }
        $i++;
      }
      if $depth == 0 {
        my $inner = $text.substr($start, $i - $start - 1);
        given $ch {
          when 'L' {
            my ($label, $target) = $inner.split('|', 2);
            my $label-text = inline-pod-pieces($label // $target).map({ $_ ~~ Pair ?? $_.value !! $_ }).join('');
            push-code-piece(%COLORS<link>, $label-text);
          }
          when 'C' | 'B' | 'I' | 'V' | 'R' | 'X' | 'E' | 'N' {
            push-nested-code-piece(%COLORS{"format_$ch"}, $inner);
          }
          default {
            flush-buf;
            push-plain-piece($inner);
          }
        }
        $pos = $i;
        next;
      }
    }
    $buf ~= $ch;
    $pos++;
  }
  flush-buf;
  flush-pieces;
  @lines;
}

multi render(\pane, Pod::Defn $pod) is export {
  debug-pod(pane, $pod);
  my $term = strip-formatting-codes($pod.term);
  pane.put: "";
  pane.put: [ %COLORS<item_1> => $term ];
  for $pod.contents -> $c {
    next unless $c ~~ Pod::Block::Para && $c.contents;
    for $c.contents -> $item {
      if $item ~~ Str {
        for defn-body-lines($item) -> $line {
          if $line ~~ Pair && $line.key eq 'marker' {
            pane.put: [ '    ', %COLORS<code> => $line.value ];
          } else {
            pane.put: [ '    ', |$line ], :wrap<word>, meta => :$pod;
          }
        }
      } else {
        pane.put: [ '    ', render($item) ], :wrap<word>, meta => :$pod;
      }
    }
  }
}

multi render(Pod::Defn $pod, Bool :$plain) is export {
  my $term = strip-formatting-codes($pod.term);
  my $body = $pod.contents.map({ $_ ~~ Str ?? $_ !! render($_, :plain) }).join(' ');
  return "$term $body" if $plain;
  %COLORS<item_1> => "$term $body"
}

multi render(\pane, Pod::Block::Code $pod) is export {
  debug-pod(pane, $pod);
  pane.put: "--code start--" if $*debug-pod;
  # $pod.contents is a flat mix of Str and Pod::FormattingCode (eg. R<>)
  # fragments, with lone "\n" Str elements marking line boundaries; group
  # the fragments back into whole logical lines before printing them.
  my @lines;
  my $current = '';
  for $pod.contents -> $c {
    if $c ~~ Str && $c eq "\n" {
      @lines.push: $current;
      $current = '';
    } else {
      $current ~= $c ~~ Str ?? $c !! render($c, :plain);
    }
  }
  @lines.push: $current if $current ne '';
  my $i = 1;
  for @lines -> $line {
    last if $i++ == @lines.elems && $line !~~ /\S/;
    next unless $line ~~ /\S/;
    pane.put: [ %COLORS<code> => $line.indent(4) ];
  }
  pane.put: "--code end--" if $*debug-pod;
}

sub render-all(\pane, @pod) is export {
  for @pod[0].contents -> $c {
    render(pane, $c);
  }
}

multi render(\pane, Str $pod) is export {
  pane.put: [ %COLORS<text> => $pod], :wrap<word>;
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
      return $pod.contents.map({render($_, :plain )}).join(' ') if $plain;
      %COLORS<link> => $pod.contents.map({render($_, :plain )}).join(' ')
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
  pane.put: [ %COLORS<default> => $pod.raku], :wrap<word>;
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

