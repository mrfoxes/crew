#!/bin/sh
# A spawned clone keeps its crew when the agent drops CREW_DIR. All Git
# repositories and configuration are temporary; terminal operations are faked.
#
#   sh test/run.sh association

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

export GIT_CONFIG_GLOBAL="$tmp/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global user.name Test
git config --global user.email test@example.com
tmp=$(cd "$tmp" && pwd -P)
git init -q --bare -b main "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/project space" 2>/dev/null
cd "$tmp/project space" || exit 1
git commit -q --allow-empty -m first
git push -q origin HEAD:main
association_dir=$(crew_init)
association_clone="$tmp/project space-ada"
term_spawn() { echo tmux:%9; }
term_name() { :; }
term_color() { :; }
crew_spawn ada --clone claude >/dev/null 2>&1

from_clone() (
    unset CREW_DIR
    cd "$association_clone/${1:-.}" || exit 1
    sh "$CREW_HOME/bin/crew" dir
)

check "spawn records the absolute crew path locally" "$association_dir" "$(git -C "$association_clone" config --local --get crew.dir)"
check "the clone finds its crew without CREW_DIR" "$association_dir" "$(from_clone)"
mkdir -p "$association_clone/nested/deeper"
check "a nested clone directory finds the same crew" "$association_dir" "$(from_clone nested/deeper)"
check "the association changes no tracked files" "" "$(git -C "$association_clone" status --porcelain)"

# Explicit routing and a nearer crew still take precedence over the link.
check "CREW_DIR takes precedence" "$tmp/explicit" "$(cd "$association_clone" && CREW_DIR="$tmp/explicit" sh "$CREW_HOME/bin/crew" dir)"
association_near=$(cd "$association_clone" && crew_init)
check "a nearer .crew takes precedence" "$association_near" "$(from_clone nested/deeper)"
rm -rf "$association_near"

git -C "$association_clone" config --local crew.dir "$tmp/gone"
check "a stale association fails" "1" "$(from_clone 2>"$tmp/stale.err"; echo $?)"
check "the stale path is named" "1" "$(grep -F -c "$tmp/gone" "$tmp/stale.err")"
mkdir "$tmp/empty"
git -C "$association_clone" config --local crew.dir "$tmp/empty"
check "an uninitialized directory is rejected" "1" "$(from_clone 2>"$tmp/stale.err"; echo $?)"
check "the uninitialized path is named" "1" "$(grep -F -c "$tmp/empty" "$tmp/stale.err")"

# A global default must not silently route an unrelated repository to a crew.
git -C "$association_clone" config --local --unset crew.dir
git config --global crew.dir "$association_dir"
check "a global crew.dir is not a clone association" "1" "$(from_clone 2>/dev/null; echo $?)"
git config --global --unset crew.dir

crew_spawn ada --clone claude >/dev/null 2>&1
check "a reused clone records the association too" "$association_dir" "$(git -C "$association_clone" config --local --get crew.dir)"
crew_leave ada >/dev/null 2>&1
check "leave without --clone keeps the association" "$association_dir" "$(from_clone)"

finish
