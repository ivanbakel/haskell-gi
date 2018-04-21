### 3.0.16

+ Remove enable-overloading flags, and use instead explicit CPP checks for 'haskell-gi-overloading-1.0', see [how to disable overloading](https://github.com/haskell-gi/haskell-gi/wiki/Overloading\#disabling-overloading).

### 3.0.12

Fix a mistake in the introspection data in [bufferIterBackwardToContextClassToggle](https://hackage.haskell.org/package/gi-gtksource/docs/GI-GtkSource-Objects-Buffer.html#v:bufferIterBackwardToContextClassToggle) and [bufferIterForwardToContextClassToggle](https://hackage.haskell.org/package/gi-gtksource/docs/GI-GtkSource-Objects-Buffer.html#v:bufferIterForwardToContextClassToggle), fixes [#75](https://github.com/haskell-gi/haskell-gi/issues/75).