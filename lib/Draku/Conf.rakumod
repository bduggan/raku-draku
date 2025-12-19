#!raku
my $draku-home = (%*ENV<XDG_CONFIG_HOME>.?IO // $*HOME.child('.config')).child('draku');

our $cache-dir is export = $draku-home.child('.doku-cache');
our $pod-dir is export = $draku-home.child('.doku-pod');
our $pod-tmp is export = $draku-home.child('.doku-pod').child('out.pod');

mkdir $draku-home unless $draku-home.d;
mkdir $pod-dir unless $pod-dir.d;
mkdir $cache-dir unless $cache-dir.d;

