# SPDX-License-Identifier: MIT
#
# `{ pkgs, systemd ? pkgs.systemd }` to a package with the programs that
# start the managed Emacs daemon and connect to it, for the `extraPaths`
# of a nemacs configuration:
#
# - `emacsclient-desktop-launcher` opens a new frame. The desktop entry
#   runs it.
# - `emacsclient-editor-launcher` opens a file in a frame that exists,
#   and waits until the file is done. `$EDITOR` runs it.
# - `ch-emacs-config-daemon-ensure`, which both run first, makes the
#   daemon of the editor they were started from the daemon that holds
#   the socket.
#
# Each program finds `emacs` and `emacsclient` in the directory it was
# started from, so a program started by its path in a Nix profile uses
# the editor the profile points at when it starts, and a program
# started by a path in the Nix store uses that editor.
#
# The daemon is a transient systemd user unit named by the generation
# of the editor: the 12 characters of the hash in the store path of the
# `emacs` binary. The unit runs `emacs --fg-daemon=server`, which binds
# the socket `$XDG_RUNTIME_DIR/emacs/server`. When another generation
# holds that socket, `ch-emacs-config-daemon-ensure` renames the socket
# to `server-drain-<pid>` and calls `ch-emacs-config-daemon-taint`
# (inits/daemon.el) in that daemon, which then closes when its last
# frame does.
{
  pkgs,
  systemd ? pkgs.systemd,
}:
let
  inherit (pkgs) lib;

  runtimeInputs = [
    systemd
    pkgs.coreutils
    pkgs.util-linux
  ];

  # The parts the three programs share: where the client and the socket
  # are, and the generation hash function.
  prelude = ''
    ${builtins.readFile ./emacs-gen-hash.sh}
    here=$(dirname "$0")
    client="$here/emacsclient"
    socket_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/emacs"
    canonical="$socket_dir/server"
  '';

  ensure = pkgs.writeShellApplication {
    name = "ch-emacs-config-daemon-ensure";
    inherit runtimeInputs;
    text = ''
      ${prelude}
      emacs="$here/emacs"
      gen=$(emacs_gen_hash "$emacs") || gen=default

      mkdir -p "$socket_dir"
      chmod 700 "$socket_dir"

      # Two launches at once would each retire the daemon that holds the
      # socket, so one waits for the other.
      exec 9>"$socket_dir/ensure.lock"
      flock 9

      state=$(systemctl --user show "emacs-daemon-$gen.service" \
        --property=ActiveState --value 2>/dev/null || echo inactive)
      if [ "$state" = active ]; then
        exit 0
      fi

      # Remove the sockets of retired daemons that are gone. A retired
      # daemon removes its socket when it exits normally, and does not
      # when it is killed.
      for drain in "$socket_dir"/server-drain-*; do
        [ -S "$drain" ] || continue
        "$client" --socket-name="$drain" --eval t >/dev/null 2>&1 || rm -f "$drain"
      done

      # Retire the daemon that holds the socket. The socket is renamed
      # first, so that a client connecting now finds no daemon, rather
      # than finding the old one. The daemon is then told, through the
      # renamed socket, that a newer one replaces it.
      if [ -S "$canonical" ]; then
        old_pid=$("$client" --socket-name="$canonical" --eval '(emacs-pid)' 2>/dev/null \
          | tr -cd '0-9' || true)
        if [ -n "$old_pid" ]; then
          drain_name="server-drain-$old_pid"
          mv "$canonical" "$socket_dir/$drain_name" 2>/dev/null || true
          "$client" --socket-name="$socket_dir/$drain_name" \
            --eval "(when (fboundp 'ch-emacs-config-daemon-taint) (ch-emacs-config-daemon-taint \"$drain_name\"))" \
            >/dev/null 2>&1 || true
        else
          # Nothing answers on the socket: a daemon that was killed left
          # the file, and a client that meets it fails.
          rm -f "$canonical"
        fi
      fi

      # `Type=notify` makes this return once the daemon has bound the
      # socket.
      systemd-run --user --quiet --collect \
        --unit="emacs-daemon-$gen" \
        --description="Emacs daemon (generation $gen)" \
        --property=Type=notify \
        --property=Restart=no \
        --property=StandardInput=null \
        --property=After=graphical-session-pre.target \
        --property=PartOf=graphical-session.target \
        "$emacs" --fg-daemon=server || true
    '';
  };

  desktopLauncher = pkgs.writeShellApplication {
    name = "emacsclient-desktop-launcher";
    inherit runtimeInputs;
    text = ''
      ${prelude}
      "$here/ch-emacs-config-daemon-ensure"
      exec "$client" --socket-name="$canonical" --create-frame --no-wait "$@"
    '';
  };

  editorLauncher = pkgs.writeShellApplication {
    name = "emacsclient-editor-launcher";
    inherit runtimeInputs;
    text = ''
      ${prelude}
      "$here/ch-emacs-config-daemon-ensure"
      exec "$client" --socket-name="$canonical" "$@"
    '';
  };
in
pkgs.symlinkJoin {
  name = "ch-emacs-config-daemon-launchers";
  paths = [
    ensure
    desktopLauncher
    editorLauncher
  ];
  meta = {
    description = "The programs that start the managed Emacs daemon and connect to it";
    platforms = lib.platforms.linux;
  };
}
