unit class Draku;

=begin pod

=head1 NAME

Draku -- Documentation viewer for Raku

=head1 SYNOPSIS

  # Browse installed modules and core docs
  draku

  # View inline documentation for a module
  draku Color

  # Get the docs from an ecosystem for a module
  draku AccountableBagHash

  # Search the core docs for a phrase
  draku search List

  # Render a single rakudoc file in the console
  draku ./my-module.rakudoc

=head1 DESCRIPTION

This is a system for viewing raku pod in a terminal console.

It finds modules and extracts inline documentation.

It also greps through the core documentation.

It will also look the ecosystems if a module is not installed locally.

Data is stored in ~/.config/draku or the equivalent if XDG_CONFIG_HOME is set.

L<Screenshots!|https://github.com/bduggan/raku-draku/wiki/screenshots>

Things that are currently supported:

* listing and browsing modules

* searching through core documentation

* rendering pod in the console and scrolling through it

* various pod elements: titles, subtitles, headings etc

* ecosystems

=head1 TODO

More documentation!  More features!

=head1 AUTHOR

Brian Duggan

=end pod
