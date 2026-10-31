#!/bin/sh
# The clone tests: a member's own clone next to the project, made from the
# checkout and pointed at its origin, with the project's identity and
# caches; reused and fast-forwarded, or left alone with changes; shown on
# the board; removed by leave only when nothing is left. All with git in
# temporary directories, a bare repository for origin: no network, no pane.
#
#   sh test/run.sh clone

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

# A global identity that is not the project's, as on the owner's machine.
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --global user.name "Work Name"
git config --global user.email "work@example.com"
export GIT_CONFIG_NOSYSTEM=1

# The paths as git prints them, symbolic links resolved.
tmp=$(cd "$tmp" && pwd -P)
git init -q --bare -b main "$tmp/origin.git"
mkdir -p "$tmp/work"
git clone -q "$tmp/origin.git" "$tmp/work/proj" 2>/dev/null
cd "$tmp/work/proj" || exit 1
git config user.name "Project Name"
git config user.email "project@example.com"
echo one >a.txt
echo ".lake/" >.gitignore
git add a.txt .gitignore
git commit -q -m "first"
git push -q origin HEAD:main
mkdir .lake
echo built >.lake/artifact
dir=$(crew_init)

# The line spawn hands the terminal, recorded.
term_spawn() { printf '%s\n' "$2" >"$tmp/line"; echo tmux:%9; }
term_name() { :; }
term_color() { :; }
ada=$tmp/work/proj-ada

crew_spawn ada --clone --cache .lake --cache nothing claude >"$tmp/out" 2>"$tmp/err"
check "the clone is next to the project" "yes" "$([ -d "$ada/.git" ] && echo yes)"
check "its origin is the project's" "$tmp/origin.git" "$(git -C "$ada" remote get-url origin)"
check "it is on main" "main" "$(git -C "$ada" symbolic-ref --short HEAD)"
check "at origin/main" "$(git -C "$ada" rev-parse origin/main)" "$(git -C "$ada" rev-parse HEAD)"
check "main follows origin/main" "origin/main" "$(git -C "$ada" rev-parse --abbrev-ref "main@{upstream}")"
check "the project's name is copied" "Project Name" "$(git -C "$ada" config --local user.name)"
check "the project's email is copied" "project@example.com" "$(git -C "$ada" config --local user.email)"
check "the cache is copied" "built" "$(cat "$ada/.lake/artifact")"
check "it says what it copied" "1" "$(grep -c 'copied .lake into the clone' "$tmp/err")"
check "it says what the project lacks" "1" "$(grep -c 'no nothing to copy' "$tmp/err")"
check "the line runs in the clone, in this crew" "cd $ada && export CREW_DIR=$dir && claude" "$(cat "$tmp/line")"
check "the clone is recorded" "$ada" "$(cat "$dir/clones/ada")"
check "the pane is recorded" "tmux:%9" "$(cat "$dir/panes/ada")"
check "spawn says the pane" "ada: tmux:%9" "$(cat "$tmp/out")"

# A spawn without --clone stays in the project.
crew_spawn bob claude >/dev/null 2>&1
check "no clone, no change" "cd $tmp/work/proj && claude" "$(cat "$tmp/line")"
check "no clone is recorded" "no" "$([ -e "$dir/clones/bob" ] && echo yes || echo no)"
check "--cache alone is refused" "2" "$(crew_spawn bob --cache .lake claude >/dev/null 2>&1; echo $?)"

# A commit lands on origin: the next spawn fast-forwards the clone.
git clone -q "$tmp/origin.git" "$tmp/other" 2>/dev/null
echo two >"$tmp/other/b.txt"
git -C "$tmp/other" add b.txt
git -C "$tmp/other" -c user.name=o -c user.email=o@example.com commit -q -m "second"
git -C "$tmp/other" push -q origin HEAD:main
check "the clone is behind once origin moves and it fetches" "1" "$(git -C "$ada" fetch -q origin; git -C "$ada" rev-list --count HEAD..origin/main)"
printf 'Agent: ada\n' | crew_write status ada >/dev/null
board=$(crew_board 1)
check "the board shows the clone and how far behind" "clone: $ada, 1 behind origin/main" "$(printf '%s\n' "$board" | grep '^clone:')"
check "the board is quiet when the identity is the same" "0" "$(printf '%s\n' "$board" | grep -c IDENTITY)"
crew_spawn ada --clone claude >/dev/null 2>&1
check "a second spawn reuses and fast-forwards" "second" "$(git -C "$ada" log -1 --format=%s)"
check "and the cache stays" "built" "$(cat "$ada/.lake/artifact")"
check "the board has it level now" "clone: $ada, 0 behind origin/main" "$(crew_board 1 | grep '^clone:')"

# A clone whose identity was lost shows on the board.
git -C "$ada" config --local --unset user.email
check "the board flags another identity" "clone: $ada, 0 behind origin/main, IDENTITY work@example.com (the project: project@example.com)" "$(crew_board 1 | grep '^clone:')"
git -C "$ada" config --local user.email project@example.com

# Changes: the clone is left as it is, and spawn stops.
echo dirty >"$ada/untracked.txt"
echo '' >"$tmp/line"
check "a clone with changes stops the spawn" "1" "$(crew_spawn ada --clone claude >/dev/null 2>&1; echo $?)"
check "and says so" "1" "$(crew_spawn ada --clone claude 2>&1 | grep -c 'has changes; left as it is')"
check "and opens no pane" "" "$(cat "$tmp/line")"
rm "$ada/untracked.txt"

# Another origin: left as it is.
git -C "$ada" remote set-url origin "$tmp/elsewhere.git"
check "a clone of another origin stops the spawn" "1" "$(crew_spawn ada --clone claude 2>&1 >/dev/null | grep -c 'is not a clone of')"
git -C "$ada" remote set-url origin "$tmp/origin.git"

# A project with no origin has nothing to clone.
git init -q "$tmp/noorigin"
cd "$tmp/noorigin" || exit 1
crew_init >/dev/null
check "a project with no origin" "1" "$(crew_spawn zed --clone claude 2>&1 >/dev/null | grep -c 'has no origin')"
cd "$tmp/work/proj" || exit 1

# Leave: an unpushed commit keeps the clone and lists it.
echo three >"$ada/c.txt"
git -C "$ada" add c.txt
git -C "$ada" commit -q -m "third, not pushed"
check "leave without --clone keeps the clone" "yes" "$(crew_leave ada >/dev/null; [ -d "$ada" ] && [ -s "$dir/clones/ada" ] && echo yes)"
check "and says where it is" "1" "$(crew_spawn ada --clone claude >/dev/null 2>&1; crew_leave ada 2>&1 | grep -c "its clone stays at $ada")"
check "leave --clone keeps one with an unpushed commit" "1" "$(crew_leave ada --clone >/dev/null 2>&1; echo $?)"
check "it lists the commit" "  commit $(git -C "$ada" rev-parse --short HEAD) third, not pushed" "$(crew_leave ada --clone 2>&1 >/dev/null | sed -n 2p)"
check "the clone stays" "yes" "$([ -d "$ada" ] && echo yes)"
echo dirty >"$ada/untracked.txt"
check "it lists a changed file too" "  file ?? untracked.txt" "$(crew_leave ada --clone 2>&1 >/dev/null | sed -n 3p)"
rm "$ada/untracked.txt"

# Pushed, nothing left: leave --clone removes it.
git -C "$ada" push -q origin HEAD:main
git -C "$ada" fetch -q origin
# A stash alone keeps the clone, and is listed.
echo stashed >>"$ada/c.txt"
git -C "$ada" stash -q
check "leave --clone keeps one holding only a stash" "1" "$(crew_leave ada --clone >/dev/null 2>&1; echo $?)"
check "it lists the stash" "  stash $(git -C "$ada" stash list)" "$(crew_leave ada --clone 2>&1 >/dev/null | sed -n 2p)"
check "the clone with a stash stays" "yes" "$([ -d "$ada" ] && echo yes)"
git -C "$ada" stash drop -q
check "leave --clone removes a clone with nothing left" "removed" "$(crew_leave ada --clone | sed -n 2p | grep -o removed)"
check "the clone is gone" "no" "$([ -e "$ada" ] && echo yes || echo no)"
check "and forgotten" "no" "$([ -e "$dir/clones/ada" ] && echo yes || echo no)"
check "a member with no clone" "0" "$(crew_leave ada --clone >/dev/null; echo $?)"
check "leave takes nothing but --clone" "2" "$(crew_leave ada --all >/dev/null 2>&1; echo $?)"

# Origin with no main: the project's branch.
git init -q --bare -b trunk "$tmp/trunk.git"
git clone -q "$tmp/trunk.git" "$tmp/work/tp" 2>/dev/null
git -C "$tmp/work/tp" config user.email t@example.com
echo t >"$tmp/work/tp/t.txt"
git -C "$tmp/work/tp" add t.txt
git -C "$tmp/work/tp" commit -q -m t
git -C "$tmp/work/tp" push -q origin HEAD:trunk
git -C "$tmp/work/tp" checkout -q -B trunk
cd "$tmp/work/tp" || exit 1
tdir=$(crew_init)
crew_spawn eve --clone claude >/dev/null 2>"$tmp/err"
check "a project whose origin has no main" "trunk" "$(git -C "$tmp/work/tp-eve" symbolic-ref --short HEAD)"
check "it says so" "1" "$(grep -c 'origin has no main: the clone works on trunk' "$tmp/err")"
printf 'Agent: eve\n' | CREW_DIR=$tdir crew_write status eve >/dev/null
check "the board counts against that branch" "clone: $tmp/work/tp-eve, 0 behind origin/trunk" "$(CREW_DIR=$tdir crew_board 1 | grep '^clone:')"

finish
