#!/bin/bash

GHCID_FILE=./ghcid.txt

echo '...' > "$GHCID_FILE"
emacsclient "$GHCID_FILE" &

COMMAND='nix-shell --run "cabal repl enumerate-function"'
ghcid -o "$GHCID_FILE" --command "$COMMAND"

