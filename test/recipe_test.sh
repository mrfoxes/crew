#!/bin/sh
# Recipes: the ones crew ships listed, read whole, their mode section cut
# out, their files installed into a member's work directory and never over
# one that differs; the owner's recipe of a name wins; crew help names them.
# The recipes' own scripts parse, and the mesh's stream filter picks the
# messages it says, from messages written here.
#
#   sh test/run.sh recipe

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

crew=$CREW_HOME/bin/crew
shipped=$CREW_HOME/share/recipes

# What crew ships.
check "the recipes crew ships" "mesh star" "$(recipe_names | tr '\n' ' ' | sed 's/ $//')"
for r in star mesh; do
    check "$r has a title" "1" "$(sed -n '1p' "$shipped/$r/recipe.md" | grep -c '^# Crew ')"
    check "$r has a mode section" "0" "$(recipe_mode "$shipped/$r/recipe.md" >/dev/null; echo $?)"
    check "$r's preset is read" "0" "$(crewfile_read "$CREW_HOME/share/presets/$r" >/dev/null 2>&1; echo $?)"
    for f in "$shipped/$r"/*.sh; do
        check "$r's $(basename "$f") parses" "0" "$(sh -n "$f" 2>&1; echo $?)"
    done
    if command -v zsh >/dev/null 2>&1; then
        check "$r's chat.zsh parses" "0" "$(zsh -n "$shipped/$r/chat.zsh" 2>&1; echo $?)"
    fi
done

# The list, and crew help naming the recipes after the protocol.
list=$("$crew" recipe)
check "the list says what recipes are" "Recipes: whole crew setups, for the agent that brings one up." "$(printf '%s\n' "$list" | sed -n 1p)"
check "the list names mesh with its title" "1" "$(printf '%s\n' "$list" | grep -c '^  mesh  *Crew mesh: ')"
check "the list ends with how to read one" "Read one with 'crew recipe <name>'." "$(printf '%s\n' "$list" | tail -n 1)"
help=$("$crew" help)
check "help starts with the protocol" "# The crew protocol" "$(printf '%s\n' "$help" | sed -n 1p)"
check "help names the recipes at its end" "## Recipes here" "$(printf '%s\n' "$help" | grep '^## ' | tail -n 1)"
check "help's last recipe" "1" "$(printf '%s\n' "$help" | tail -n 1 | grep -c '^  star  *Crew star: ')"

# One recipe whole, and its mode section alone.
check "a recipe whole" "$(cat "$shipped/mesh/recipe.md")" "$("$crew" recipe mesh)"
mode=$("$crew" recipe mesh --mode)
check "the mode section starts at its heading" "## Crew mesh mode" "$(printf '%s\n' "$mode" | sed -n 1p)"
check "the mode section stops before the next one" "0" "$(printf '%s\n' "$mode" | grep -c '^## Shape')"
check "the mode section ends on text" "1" "$(printf '%s\n' "$mode" | tail -n 1 | grep -c .)"
check "star's mode section" "## Crew mode" "$("$crew" recipe star --mode | sed -n 1p)"

# Refusals.
check "a recipe not there" "1" "$("$crew" recipe nowhere >/dev/null 2>&1; echo $?)"
check "a recipe not there names those there are" "crew: recipes: mesh star " "$("$crew" recipe nowhere 2>&1 | tail -n 1)"
check "a name crew does not take" "2" "$("$crew" recipe Mesh >/dev/null 2>&1; echo $?)"
check "two recipes" "2" "$("$crew" recipe mesh star >/dev/null 2>&1; echo $?)"
check "--mode and --install" "2" "$("$crew" recipe mesh --mode --install hq-lead >/dev/null 2>&1; echo $?)"
check "--install with no member" "2" "$("$crew" recipe mesh --install >/dev/null 2>&1; echo $?)"
check "--mode with no recipe" "2" "$("$crew" recipe --mode >/dev/null 2>&1; echo $?)"
check "an unknown flag" "2" "$("$crew" recipe mesh --all >/dev/null 2>&1; echo $?)"
mkdir -p "$XDG_CONFIG_HOME/crew/recipes/bare"
printf '# Crew bare\n\nNo mode here.\n' >"$XDG_CONFIG_HOME/crew/recipes/bare/recipe.md"
check "a recipe with no mode section" "1" "$("$crew" recipe bare --mode >/dev/null 2>&1; echo $?)"

# The owner's recipe of a name wins, and is listed once.
mkdir -p "$XDG_CONFIG_HOME/crew/recipes/star"
printf '# Crew star, mine\n' >"$XDG_CONFIG_HOME/crew/recipes/star/recipe.md"
check "the owner's recipe wins" "# Crew star, mine" "$("$crew" recipe star)"
check "and is listed once" "1" "$("$crew" recipe | grep -c '^  star ')"
check "with its own title" "1" "$("$crew" recipe | grep -c '^  star  *Crew star, mine$')"
rm -r "$XDG_CONFIG_HOME/crew/recipes"

# Installing into a member's work directory.
git init -q "$tmp/repo"
git -C "$tmp/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
cd "$tmp/repo" || exit 1
dir=$(crew_init)
out=$("$crew" recipe mesh --install hq-lead)
check "install says each file" "chat.zsh ctx.sh playbook-keeper.md stream.sh stuck.sh" "$(printf '%s\n' "$out" | sed 's|.*/||' | tr '\n' ' ' | sed 's/ $//')"
check "into the member's work directory" "1" "$(printf '%s\n' "$out" | grep -c "^$dir/work/hq-lead/stuck.sh$")"
check "not the recipe itself" "1" "$([ ! -e "$dir/work/hq-lead/recipe.md" ] && echo 1)"
check "scripts executable" "1" "$([ -x "$dir/work/hq-lead/stuck.sh" ] && [ -x "$dir/work/hq-lead/chat.zsh" ] && echo 1)"
check "a playbook is not" "1" "$([ ! -x "$dir/work/hq-lead/playbook-keeper.md" ] && echo 1)"
check "the same files again" "0" "$("$crew" recipe mesh --install hq-lead >/dev/null 2>&1; echo $?)"
echo "# mine" >>"$dir/work/hq-lead/stuck.sh"
check "a file that differs is kept" "1" "$("$crew" recipe mesh --install hq-lead >/dev/null 2>&1; echo $?)"
check "and named" "1" "$("$crew" recipe mesh --install hq-lead 2>&1 >/dev/null | grep -c 'stuck.sh differs')"
check "with its change" "# mine" "$(tail -n 1 "$dir/work/hq-lead/stuck.sh")"
check "a member name crew does not take" "2" "$("$crew" recipe mesh --install HQ >/dev/null 2>&1; echo $?)"

# The mesh's stream filter, on messages written here: stream.sh runs for a
# moment in the background and its output is read.
msgs=$tmp/stream
mkdir -p "$msgs/messages" "$msgs/work/hq-lead"
msg() {
    printf '# %s. %s to %s: %s\n\nFrom: %s\nTo: %s\nTime: x\n\nbody\nTo: owner\n' "$1" "$2" "$3" "$4" "$2" "$3" >"$msgs/messages/$1-$2-to-$3-x.md"
}
msg 0001 owner hq-lead "Owner: go"
msg 0002 hq-lead api-coord "Plan: api"
msg 0003 api-coord api-dev1 "Plan: lane 1"
msg 0004 api-coord web-coord "Contract: user-api"
msg 0005 api-dev1 api-coord "Question: x"
msg 0006 web-dev1 web-coord "Pushed: abc"
stream() {
    printf '%s\n' "$1" >"$msgs/work/hq-lead/stream.filter"
    sh "$shipped/mesh/stream.sh" "$msgs" >"$tmp/stream.out" 2>&1 &
    pid=$!
    sleep 1
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    sed -n 's/^.*\(00[0-9][0-9]\)-.*-x\.md.*$/\1/p' "$tmp/stream.out" | tr '\n' ' ' | sed 's/ $//'
}
check "the filter hq" "0001 0002" "$(stream hq)"
check "an area" "0001 0002 0003 0004 0005" "$(stream api)"
check "the last 5 that match" "0002 0003 0004 0005 0006" "$(stream '*')"
check "a subject" "0001 0004" "$(stream Contract:)"
check "a role across areas" "0003 0005 0006" "$(stream dev1 | tr ' ' '\n' | grep -v 0001 | tr '\n' ' ' | sed 's/ $//')"
check "an empty filter is hq" "0001 0002" "$(stream '')"
check "a To: in the body routes nothing" "0001 0002" "$(stream hq-lead)"

finish
