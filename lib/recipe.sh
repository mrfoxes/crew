# Recipes: whole crew setups, written for the agent that brings one up. A
# recipe is a directory, the owner's in ${XDG_CONFIG_HOME:-~/.config}/crew/
# recipes/<name>/ or one crew ships in share/recipes/<name>/; the owner's of
# the same name wins. It holds recipe.md, whose first line is "# <title>",
# and the files its bring-up installs into a member's work directory:
# scripts and playbooks. The section of recipe.md whose heading ends in
# " mode" is what every member of that setup follows. Sourced by bin/crew.

# The directory of the recipe <name>: the owner's when there is one.
recipe_dir() {
    if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/crew/recipes/$1/recipe.md" ] ||
        [ ! -f "$CREW_HOME/share/recipes/$1/recipe.md" ]; then
        echo "${XDG_CONFIG_HOME:-$HOME/.config}/crew/recipes/$1"
    else
        echo "$CREW_HOME/share/recipes/$1"
    fi
}

# The names of the recipes there are, the owner's and crew's, one a line.
recipe_names() {
    for r_d in "${XDG_CONFIG_HOME:-$HOME/.config}/crew/recipes"/* "$CREW_HOME/share/recipes"/*; do
        [ -f "$r_d/recipe.md" ] && basename "$r_d"
    done | awk '!seen[$0]++' | sort
}

# Each recipe with its title, one a line, indented.
recipe_index() {
    for r_n in $(recipe_names); do
        printf '  %-10s %s\n' "$r_n" "$(sed -n '1s/^# *//p' "$(recipe_dir "$r_n")/recipe.md")"
    done
}

# What crew help adds after the protocol: the recipes there are, if any.
recipe_help() {
    r_list=$(recipe_index)
    [ -n "$r_list" ] || return 0
    printf '\n## Recipes here\n\n%s\n' "$r_list"
}

# The section of <file> whose "## " heading ends in " mode", heading
# included, to the next "## " heading, without the blank lines it ends on.
recipe_mode() {
    awk '
        /^## / { on = ($0 ~ / mode$/) }
        !on { next }
        $0 == "" { blank++; next }
        { while (blank > 0) { print ""; blank-- } print; found = 1 }
        END { exit !found }' "$1"
}

# Copies the files of the recipe in <recipe dir> but recipe.md into
# work/<member>/ of the crew <dir>, scripts executable. A file there that
# differs is never replaced: it is named, and the copy fails.
recipe_install() {
    r_to=$1/work/$3
    mkdir -p "$r_to" || return 1
    r_status=0
    for r_f in "$2"/*; do
        r_base=$(basename "$r_f")
        [ -f "$r_f" ] && [ "$r_base" != recipe.md ] || continue
        if [ -e "$r_to/$r_base" ] && ! cmp -s "$r_f" "$r_to/$r_base"; then
            echo "crew: $r_to/$r_base differs from the recipe's: kept; remove it to install the recipe's" >&2
            r_status=1
            continue
        fi
        cp "$r_f" "$r_to/$r_base" || return 1
        case "$r_base" in *.sh | *.zsh | *.bash) chmod +x "$r_to/$r_base" ;; esac
        echo "$r_to/$r_base"
    done
    return "$r_status"
}

# crew recipe [<recipe>] [--mode | --install <member>]: with no recipe, the
# recipes there are; else the recipe whole, its mode section alone, or its
# files installed into the member's work directory.
crew_recipe() {
    r_usage="usage: crew recipe [<recipe>] [--mode | --install <member>]"
    r_name=""
    r_do=show
    r_member=""
    while [ $# -gt 0 ]; do
        case "$1" in
        --mode)
            [ "$r_do" = show ] || { echo "$r_usage" >&2 && return 2; }
            r_do=mode
            ;;
        --install)
            [ "$r_do" = show ] && [ $# -ge 2 ] || { echo "$r_usage" >&2 && return 2; }
            r_do=install
            r_member=$2
            shift
            ;;
        -*)
            echo "$r_usage" >&2
            return 2
            ;;
        *)
            [ -z "$r_name" ] || { echo "$r_usage" >&2 && return 2; }
            r_name=$1
            ;;
        esac
        shift
    done
    if [ -z "$r_name" ]; then
        [ "$r_do" = show ] || { echo "$r_usage" >&2 && return 2; }
        r_list=$(recipe_index)
        if [ -z "$r_list" ]; then
            echo "crew: no recipes" >&2
            return 1
        fi
        echo "Recipes: whole crew setups, for the agent that brings one up."
        printf '%s\n' "$r_list"
        echo "Read one with 'crew recipe <name>'."
        return
    fi
    crew_name "$r_name" || return 2
    r_dir=$(recipe_dir "$r_name")
    if [ ! -f "$r_dir/recipe.md" ]; then
        echo "crew: no recipe $r_name at $r_dir" >&2
        echo "crew: recipes: $(recipe_names | tr '\n' ' ')" >&2
        return 1
    fi
    case "$r_do" in
    show) cat "$r_dir/recipe.md" ;;
    mode)
        recipe_mode "$r_dir/recipe.md" || {
            echo "crew: the recipe $r_name has no section whose heading ends in ' mode'" >&2
            return 1
        }
        ;;
    install)
        crew_name "$r_member" || return 2
        dir=$(crew_dir) || return 1
        recipe_install "$dir" "$r_dir" "$r_member"
        ;;
    esac
}
