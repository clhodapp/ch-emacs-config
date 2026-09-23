# SPDX-License-Identifier: MIT
# emacs_gen_hash BIN — print the 12-char store hash of the Emacs
# package BIN resolves into: the systemd instance name of that
# generation's daemon.  The single implementation of this derivation;
# the HM activation script and the emacsclient launchers both source
# it.  Fails (non-zero, no output) when BIN does not resolve into the
# Nix store.
emacs_gen_hash() {
  local _target
  _target=$(readlink -f "$1" 2>/dev/null) || return 1
  case $_target in
    /nix/store/*)
      _target=${_target#/nix/store/}
      printf '%s\n' "${_target:0:12}"
      ;;
    *)
      return 1
      ;;
  esac
}
