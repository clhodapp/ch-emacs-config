#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Last-frame gate check for inits/daemon.el.  Boots a bare daemon with the
# daemon init, opens real tty client frames, taints the daemon the way
# activation does, and drives the close paths with `yes-or-no-p' stubbed:
#
#   1. declining a direct `delete-frame' keeps the frame
#   2. declining the window-manager close event (`handle-delete-frame',
#      native-compiled frame.el calling the advised primitive) keeps it
#   3. declining C-x C-c on a nowait frame (`save-buffers-kill-terminal')
#      keeps it
#   4. declining C-x C-c on a blocking client's frame (the
#      `server-delete-client' path) keeps the frame and the client
#   5. deleting a frame that is not the last one never prompts
#   6. confirming deletes the last frame, asking exactly once (the
#      `server-delete-client' re-entry from `delete-frame' stays quiet)
#   7. the daemon then drains: its socket disappears
#
# Usage: EMACS=... EMACSCLIENT=... daemon-last-frame-gate.sh <daemon.el>
# Needs python3 on PATH (pty-run.py beside this script) and a short
# XDG_RUNTIME_DIR: Unix socket paths are capped at 108 bytes.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
daemon_el="$1"
sockdir="$XDG_RUNTIME_DIR/emacs"
sock="server"

ec() { "$EMACSCLIENT" --socket-name="$sockdir/$sock" --eval "$1" 2>&1; }

expect() {
  local label="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then
    echo "ok   $label: $got"
  else
    echo "FAIL $label: got $got, want $want"
    return 1
  fi
}

wait_frames() {
  local n
  for _ in $(seq 100); do
    n="$(ec '(length (frame-list))')"
    [[ "$n" == "$1" ]] && return 0
    sleep 0.1
  done
  echo "FAIL waiting for $1 frames (have $n)"
  return 1
}

"$EMACS" -Q -l "$daemon_el" --daemon=server
daemon_pid="$(ec '(emacs-pid)')"
trap 'kill "$daemon_pid" 2>/dev/null || true' EXIT

python3 "$here/pty-run.py" "$EMACSCLIENT" --socket-name="$sockdir/$sock" -t &
wait_frames 2

# Rotate the socket and taint, as home-manager activation does.
mv "$sockdir/server" "$sockdir/server-drain-test"
sock="server-drain-test"
ec '(ch-emacs-config-daemon-taint "server-drain-test")' >/dev/null
ec '(progn (require (quote cl-lib)) (defvar ch-test-prompted nil) (defvar ch-test-prompts 0) t)' >/dev/null

# The single client frame, and yes-or-no-p stubs that record being asked.
frame='(seq-find (function ch-emacs-config-daemon--client-frame-p) (frame-list))'
decline='(cl-letf (((symbol-function (quote yes-or-no-p)) (lambda (&rest _) (setq ch-test-prompted t) nil)))'
confirm='(cl-letf (((symbol-function (quote yes-or-no-p)) (lambda (&rest _) (cl-incf ch-test-prompts) t)))'
never='(cl-letf (((symbol-function (quote yes-or-no-p)) (lambda (&rest _) (error "prompted for a non-last frame"))))'
report='(list :prompted ch-test-prompted :frames (length (frame-list)))'

expect "decline delete-frame" "(:prompted t :frames 2)" \
  "$(ec "(progn (setq ch-test-prompted nil) $decline (delete-frame $frame)) $report)")"
expect "decline handle-delete-frame" "(:prompted t :frames 2)" \
  "$(ec "(progn (setq ch-test-prompted nil) $decline (handle-delete-frame (list (quote delete-frame) (list $frame)))) $report)")"
# A tty client is a blocking (process) client.  Test the nowait branch of
# save-buffers-kill-terminal by relabelling the frame for the call and
# restoring the process after; then the blocking branch as it is.
expect "decline save-buffers-kill-terminal (nowait)" "(:prompted t :frames 2)" \
  "$(ec "(progn (setq ch-test-prompted nil) (let* ((f $frame) (proc (frame-parameter f (quote client)))) (set-frame-parameter f (quote client) (quote nowait)) $decline (with-selected-frame f (save-buffers-kill-terminal))) (set-frame-parameter f (quote client) proc)) $report)")"
expect "decline save-buffers-kill-terminal (blocking client)" "(:prompted t :frames 2 :client-alive t)" \
  "$(ec "(progn (setq ch-test-prompted nil) $decline (with-selected-frame $frame (save-buffers-kill-terminal))) (list :prompted ch-test-prompted :frames (length (frame-list)) :client-alive (and (process-live-p (frame-parameter $frame (quote client))) t)))")"

python3 "$here/pty-run.py" "$EMACSCLIENT" --socket-name="$sockdir/$sock" -t &
wait_frames 3
expect "non-last frame closes silently" "(:frames 2)" \
  "$(ec "(progn $never (delete-frame (car (last (seq-filter (function ch-emacs-config-daemon--client-frame-p) (frame-list)))))) (list :frames (length (frame-list))))")"
wait_frames 2

expect "confirm delete-frame, asked once" "(:prompts 1 :frames 1)" \
  "$(ec "(progn (setq ch-test-prompts 0) $confirm (delete-frame $frame)) (list :prompts ch-test-prompts :frames (length (frame-list))))")"

for _ in $(seq 300); do
  [[ -S "$sockdir/server-drain-test" ]] || break
  sleep 0.1
done
if [[ -e "$sockdir/server-drain-test" ]]; then
  echo "FAIL daemon did not drain after its last frame was confirmed closed"
  exit 1
fi
echo "ok   daemon drained after the last frame closed"
