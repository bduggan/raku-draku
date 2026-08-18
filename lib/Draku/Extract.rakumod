unit module Draku::Extract;
use experimental :rakuast;
use Draku::Render;

multi links(RakuAST::Doc::Paragraph $para) is export {
  $para.atoms.map: { |links($_) }
}

multi links(RakuAST::Doc::Markup $markup) is export {
  return Empty unless $markup.letter eq 'L';
  return ( { name => ~render($markup, :plain), target => $markup.meta[0] }, )
}

multi links($pod) is export {
  Empty
}
