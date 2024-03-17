#!/bin/bash

workspaceFolder=$(dirname "${BASH_SOURCE[0]}")
pushd "$workspaceFolder"

update_pijul_dep() {
  local repo
  repo="$1"

  local name
  name="deps/"$(basename "$2")

  # clear the director
  rm -rf "$name"

  pijul clone "$repo" "$name"
}

mkdir -p deps
# not using this anymore, but keeping it to show how to use the function
# update_pijul_dep https://nest.pijul.com/hardliner66/secs secs
