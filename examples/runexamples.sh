#!/bin/bash

set -e
set -x

cabal clean
haskell-gi -l Gtk WebKit2
haskell-gi -c Gtk WebKit2
cabal configure
time cabal build

export G_SLICE="debug-blocks"
export MALLOC_CHECK_=2
#export HASKELL_GI_DEBUG_MEM=1
dist/build/SimpleBrowser/SimpleBrowser
