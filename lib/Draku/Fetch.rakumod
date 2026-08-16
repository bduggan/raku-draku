unit module Draku::Fetch;
use JSON::Fast;
use Draku::Conf;

#| Ecosystem indices to search for modules that aren't installed locally.
#| Each is a URL to a JSON array of META6-style hashes (same mirrors zef
#| uses by default: fez and rea).
our %ecosystems is export =
  fez => 'https://360.zef.pm/',
  rea => 'https://raw.githubusercontent.com/Raku/REA/main/META.json',
;

my $ecosystem-dir = $cache-dir.child('ecosystems');
my $fetched-dir   = $cache-dir.child('fetched');

#| Return the (cached) parsed JSON index for one ecosystem, fetching it
#| into the draku cache dir first if it isn't there yet (or :$update is set).
sub ecosystem-index($name, Bool :$update) is export {
  mkdir $ecosystem-dir unless $ecosystem-dir.d;
  my $file = $ecosystem-dir.child("$name.json");
  if $update || !$file.e {
    my $proc = run 'curl', '-sL', '-o', $file, %ecosystems{$name};
    return Empty unless $proc.so && $file.e;
  }
  (try from-json($file.slurp)) // Empty;
}

#| Search all ecosystem indices for a module (by dist name or provided
#| module name) and return the highest-versioned match, along with the
#| mirror it came from.
sub find-candidate($module, Bool :$update) is export {
  my @matches;
  for %ecosystems.keys -> $name {
    for ecosystem-index($name, :$update) -> %dist {
      next unless %dist<name> eq $module || (%dist<provides>{$module}:exists);
      @matches.push: %( :%dist, mirror => %ecosystems{$name} );
    }
  }
  return Nil unless @matches;
  @matches.sort( { try Version.new(.<dist><version> // '0') // Version.new('0') } ).tail;
}

#| Fetch a module's source (not installed) by downloading its dist tarball
#| from the ecosystem index. Returns the extracted IO::Path, or Nil.
sub fetch-module-source($module, Bool :$update) is export {
  my $found = find-candidate($module, :$update) or return Nil;
  my %dist := $found<dist>;
  my $url = %dist<source-url> // (%dist<path> ?? $found<mirror> ~ %dist<path> !! Nil);
  return Nil without $url;

  mkdir $fetched-dir unless $fetched-dir.d;
  my $slug = "{ %dist<name>.subst('::', '-', :g) }-{ %dist<version> }";
  my $dest = $fetched-dir.child($slug);
  return $dest if $dest.d;

  my $tarball = $fetched-dir.child("$slug.tar.gz");
  my $fetch = run 'curl', '-sL', '-o', $tarball, $url;
  return Nil unless $fetch.so && $tarball.e;

  mkdir $dest;
  my $extract = run 'tar', 'xzf', $tarball, '-C', $dest, '--strip-components=1';
  unlink $tarball;
  return Nil unless $extract.so;

  $dest;
}

#| Look for rakudoc files under docs/ or doc/ in a distribution directory.
sub find-rakudoc-files(IO::Path $dist-path) is export {
  ($dist-path.child('docs'), $dist-path.child('doc'))
    .grep(*.d)
    .map({ .dir.grep(*.basename.ends-with('.rakudoc')) })
    .flat
    .sort;
}
