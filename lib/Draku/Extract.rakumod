unit module Draku::Extract;
use Draku::Render;

multi links(Pod::Block::Para $pod) is export {
  $pod.contents.map: { |links($_) }
}

multi links(Pod::FormattingCode $pod) is export {
  return Empty unless $pod.type eq 'L';
  return ( { name => ~render($pod, :plain), target => $pod.meta }, )
}

multi links($pod) is export {
  Empty
}
