# SPDX-License-Identifier: MIT
# Append-only merge of declared words into enchant's personal dictionary
# (usage: jinx-merge-personal-dict <declared-words-file> <dictionary>).
# jinx-correct's save keys rewrite that file at runtime, so it can never
# be a store symlink; activation instead converges the declared words in
# without touching anything jinx has learned since.
{ pkgs }:
pkgs.writeShellApplication {
  name = "jinx-merge-personal-dict";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.gawk
  ];
  text = ''
    declared=$1
    dict=$2
    mkdir -p "$(dirname "$dict")"
    [ -e "$dict" ] || : > "$dict"
    # Declared words not yet in the dictionary; also drops blank lines
    # and duplicates within the declared list. Files are told apart via
    # ARGV rather than NR==FNR so an empty dictionary still routes the
    # declared list to the second branch.
    missing=$(awk '
      FILENAME == ARGV[1] { present[$0] = 1; next }
      $0 != "" && !($0 in present) && !emitted[$0]++
    ' "$dict" "$declared")
    [ -n "$missing" ] || exit 0
    # Hand edits can leave the file without a trailing newline; repair
    # before appending so two words cannot fuse into one.
    if [ -s "$dict" ] && [ -n "$(tail -c1 "$dict")" ]; then
      echo >> "$dict"
    fi
    printf '%s\n' "$missing" >> "$dict"
  '';
}
