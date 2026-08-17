unit module Draku::Table;

#| Line-level grammar for the body of a =table block, per S26: a line is
#| either a horizontal separator (-, =, _, optionally mixed with + and |),
#| blank, or a row of cells. Cells are separated by gaps: two or more
#| spaces (the "double-space" rule), or a | or + padded with whitespace on
#| at least one side -- so a bare | glued to content, as in C<D<...|...>>,
#| stays inside its cell. row-line is a regex (not a token) so a trailing
#| " |" can be re-interpreted as trailing decoration when no cell follows.
grammar TableLine is export {
  # regex, not token: an alternative may match a prefix (eg. blank-line
  # matching zero characters of a row) and must be retried when $ fails
  regex TOP        { ^ [ <sep-line> || <blank-line> || <row-line> ] $ }
  token sep-line   { <[+|\h]>* <[\-=_]> <[\-=_+|\h]>* }
  token blank-line { \h* }
  regex row-line   { \h* <lead>? <cell>+ % <gap> <trail>? }
  token lead       { <[|+]> \h* }
  regex trail      { \h* <[|+]> }
  token gap        { \h* <[|+]> \h+ | \h+ <[|+]> \h* | \h ** 2..* }
  token cell       { [ <!gap> \N ]+ }
}

#| Parse a raw =table body into cell text. Rows are grouped by blank lines
#| or separator lines; a separator right after the first group marks it as
#| the header row; a single unseparated group is one row per line.
#| Piped rows assign cells by position in the line; double-space rows
#| assign them by character-column intervals, merged across all such rows,
#| which is what reassembles multi-line rows correctly. Returns a Hash
#| with <headers> (possibly empty) and <rows> of raw (un-stripped) cell
#| strings, or Nil when the body doesn't parse as a table.
sub parse-table-source(@raw) is export {
  my @lines = @raw.map({ .Str.trim-trailing });
  @lines.shift while @lines && !@lines[0].chars;
  @lines.pop   while @lines && !@lines[*-1].chars;
  return Nil unless @lines;
  my $dedent = @lines.grep(*.chars).map({ .chars - .trim-leading.chars }).min;
  @lines = @lines.map({ .chars ?? .substr($dedent) !! '' });

  my @infos;
  for @lines -> $line {
    my $m = TableLine.parse($line);
    return Nil without $m;
    if $m<sep-line>.defined {
      @infos.push: %( kind => 'sep' );
    } elsif $m<blank-line>.defined {
      @infos.push: %( kind => 'blank' );
    } else {
      my $r = $m<row-line>;
      my $piped = so $r<lead>.defined || $r<trail>.defined
        || $r<gap>.first({ .Str ~~ /<[|+]>/ });
      @infos.push: %( kind => 'row', piped => $piped,
        cells => $r<cell>.map({ %( text => .Str.trim, from => .from, to => .to ) }).List );
    }
  }

  # group row lines; note whether a visible separator follows each group
  my @groups;
  my @sep-after;
  my @cur;
  for @infos -> $info {
    if $info<kind> eq 'row' {
      @cur.push: $info;
    } else {
      if @cur {
        @groups.push: @cur.List;
        @sep-after.push: $info<kind> eq 'sep';
        @cur = ();
      } elsif $info<kind> eq 'sep' && @sep-after {
        @sep-after[*-1] = True;
      }
    }
  }
  if @cur {
    @groups.push: @cur.List;
    @sep-after.push: False;
  }
  return Nil unless @groups;

  my $has-header = @groups > 1 && @sep-after[0];
  my @header-lines = $has-header ?? @groups[0].List !! ();
  my @row-groups = $has-header ?? @groups[1..*] !! @groups;
  if @row-groups == 1 {
    @row-groups = @row-groups[0].map({ ($_,).List });
  }

  # character-column intervals of the double-space rows, merged across
  # lines (a sub-2-wide gap between fragments is part of the same column)
  my @cols;
  my @intervals = @infos.grep({ .<kind> eq 'row' && !.<piped> })
    .map({ |.<cells>.map({ (.<from>, .<to>) }) })
    .sort({ .[0] });
  for @intervals -> ($from, $to) {
    if @cols && $from <= @cols[*-1][1] + 1 {
      @cols[*-1][1] max= $to;
    } else {
      @cols.push: [$from, $to];
    }
  }

  my sub group-cells(@group-infos) {
    my @cells;
    my sub append(Int $k, Str $text) {
      return unless $text.chars;
      @cells[$k] = (@cells[$k] // '').chars ?? @cells[$k] ~ ' ' ~ $text !! $text;
    }
    for @group-infos -> $info {
      if $info<piped> || !@cols {
        append($_.key, $_.value<text>) for $info<cells>.pairs;
      } else {
        for $info<cells>.List -> $c {
          my $k = @cols.first(:k, -> $col { $col[0] <= $c<from> < $col[1] }) // @cells.elems;
          append($k, $c<text>);
        }
      }
    }
    @cells.map({ $_ // '' }).List;
  }

  %(
    headers => (@header-lines ?? group-cells(@header-lines) !! ()).List,
    rows    => @row-groups.map({ group-cells($_.List) }).List,
  );
}
