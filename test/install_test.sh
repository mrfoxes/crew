#!/bin/sh
# install.sh and crew update against a fake release: packaged by
# .github/package.sh from a repository of its own, served by a curl stub.
# A fresh install, a version asked for, an upgrade, a checksum mismatch
# that installs nothing, --prefix, both sha256sum and shasum, --uninstall,
# then crew version and crew update on what was installed.
#
#   sh test/run.sh install

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

export HOME="$tmp/home"
mkdir -p "$HOME"
export CREW_RELEASES="https://releases.test/crew"
export SHELL=/bin/zsh
real_shasum=$(command -v shasum || :)

# A release, twice: v1.0.0 and v1.1.0, the latter the latest.
mkdir -p "$tmp/src/bin" "$tmp/src/share/completions"
printf '#!/bin/sh\nself=$(readlink "$0" || echo "$0")\necho "fake crew $(cat "$(dirname "$self")/../VERSION") $*"\n' >"$tmp/src/bin/crew"
chmod +x "$tmp/src/bin/crew"
: >"$tmp/src/share/completions/crew.fish"
cp "$CREW_HOME/install.sh" "$tmp/src/install.sh"
printf '# Changelog\n\n## 1.1.0\n\n- The second.\n\n## 1.0.0\n\n- The first.\n' >"$tmp/src/CHANGELOG.md"
git init -q "$tmp/src"
g() { git -C "$tmp/src" -c user.name=t -c user.email=t@example.com "$@"; }
g add bin share install.sh CHANGELOG.md && g commit -q -m first && g tag v1.0.0
echo second >"$tmp/src/second" && g add second && g commit -q -m second && g tag v1.1.0
fake=$tmp/fake
package() { (cd "$tmp/src" && sh "$CREW_HOME/.github/package.sh" "$@"); }
check "package --dry makes nothing" "0" "$(package v1.0.0 "$fake/dry" --dry >/dev/null; [ -e "$fake/dry" ] && echo 1 || echo 0)"
check "package wants a tag" "2" "$(package 1.0.0 "$fake/x" >/dev/null 2>&1; echo $?)"
check "package wants a tag that is there" "1" "$(package v9.9.9 "$fake/x" >/dev/null 2>&1; echo $?)"
check "package makes the release" "0" "$(package v1.0.0 "$fake/download/v1.0.0" >/dev/null; echo $?)"
package v1.1.0 "$fake/download/v1.1.0" >/dev/null
mkdir -p "$fake/latest/download"
cp "$fake/download/v1.1.0/SHA256SUMS" "$fake/download/v1.1.0/install.sh" "$fake/latest/download/"
mkdir "$tmp/look" && tar -xzf "$fake/download/v1.0.0/crew-v1.0.0.tar.gz" -C "$tmp/look"
check "the tarball holds the files as they are, under crew-<tag>/" "1" "$([ -x "$tmp/look/crew-v1.0.0/bin/crew" ] && echo 1)"
check "and VERSION with the tag" "v1.0.0" "$(cat "$tmp/look/crew-v1.0.0/VERSION")"
check "and not the next version's files" "0" "$([ -e "$tmp/look/crew-v1.0.0/second" ] && echo 1 || echo 0)"
check "SHA256SUMS names the tarball and install.sh" "crew-v1.0.0.tar.gz install.sh" "$(awk '{ print $2 }' "$fake/download/v1.0.0/SHA256SUMS" | tr '\n' ' ' | sed 's/ $//')"
check "the notes are the tag's entry" "- The first." "$(cat "$fake/download/v1.0.0/notes.md")"

# A curl that serves the fake release: -o <file> <url>, the url's path
# under it.
cat >"$tmp/bin/curl" <<EOF
#!/bin/sh
out=""
url=""
while [ \$# -gt 0 ]; do
    case "\$1" in
    -o) out=\$2; shift ;;
    -*) ;;
    *) url=\$1 ;;
    esac
    shift
done
cp "$fake/\${url#$CREW_RELEASES/}" "\$out"
EOF
chmod +x "$tmp/bin/curl"
install() { sh "$CREW_HOME/install.sh" "$@" >"$tmp/install.out" 2>&1; echo $?; }
data=$HOME/.local/share/crew
check "a fresh install exits 0" "0" "$(install)"
check "it installs the latest version" "v1.1.0" "$(cat "$data/v1.1.0/VERSION")"
check "current points at it" "v1.1.0" "$(readlink "$data/current")"
check "the link runs it, and doctor ran" "fake crew v1.1.0 doctor" "$(grep '^fake crew' "$tmp/install.out")"
check "it says what it did" "1" "$(grep -c "^crew v1.1.0 installed at $data/v1.1.0, current, and linked from $HOME/.local/bin/crew$" "$tmp/install.out")"
check "it names the PATH line" "1" "$(grep -c "export PATH=\"$HOME/.local/bin:\\\$PATH\"" "$tmp/install.out")"
check "it names the completion for the shell" "1" "$(grep -c "fpath=($data/current/share/completions" "$tmp/install.out")"
check "it records the link" "$HOME/.local/bin/crew" "$(cat "$data/link")"
check "a version asked for" "0" "$(install --version v1.0.0)"
check "both versions kept, current at the asked one" "v1.0.0 v1.0.0 v1.1.0" "$(readlink "$data/current") $(for v in "$data"/v*; do basename "$v"; done | tr '\n' ' ' | sed 's/ $//')"
check "run again, it upgrades in place" "v1.1.0" "$(install >/dev/null; readlink "$data/current")"
check "--prefix links elsewhere" "$data/current/bin/crew" "$(install --prefix "$tmp/other" >/dev/null; readlink "$tmp/other/crew")"
check "and records it" "$tmp/other/crew" "$(cat "$data/link")"
check "install wants a version after --version" "2" "$(install --version)"
check "install takes no other flag" "2" "$(install --now)"

# A checksum mismatch installs nothing.
rm -rf "$data"
cp "$fake/latest/download/SHA256SUMS" "$tmp/sums.good"
awk '$2 ~ /^crew-.*\.tar\.gz$/ { $1 = (substr($1, 1, 1) == "0" ? "1" : "0") substr($1, 2) } { print $1 "  " $2 }' "$tmp/sums.good" >"$fake/latest/download/SHA256SUMS"
check "a checksum mismatch stops" "1" "$(install)"
check "and says so" "1" "$(grep -c '^install: checksum mismatch for crew-v1.1.0.tar.gz .*: nothing installed$' "$tmp/install.out")"
check "and installs nothing" "0" "$([ -e "$data" ] && echo 1 || echo 0)"
cp "$tmp/sums.good" "$fake/latest/download/SHA256SUMS"

# sha256sum where it is, shasum where it is not.
mkdir "$tmp/toolsA" "$tmp/toolsB"
printf '#!/bin/sh\necho sha256sum >>"%s"\nexec "%s" -a 256 "$@"\n' "$tmp/tool.log" "$real_shasum" >"$tmp/toolsA/sha256sum"
printf '#!/bin/sh\nexit 127\n' >"$tmp/toolsB/sha256sum"
printf '#!/bin/sh\necho shasum >>"%s"\nexec "%s" "$@"\n' "$tmp/tool.log" "$real_shasum" >"$tmp/toolsB/shasum"
chmod +x "$tmp/toolsA/sha256sum" "$tmp/toolsB/sha256sum" "$tmp/toolsB/shasum"
check "sha256sum when it is there" "sha256sum" "$(: >"$tmp/tool.log"; PATH="$tmp/toolsA:$PATH" sh "$CREW_HOME/install.sh" >/dev/null 2>&1; sort -u "$tmp/tool.log")"
check "shasum when sha256sum is not" "shasum" "$(: >"$tmp/tool.log"; PATH="$tmp/toolsB:$PATH" sh "$CREW_HOME/install.sh" >/dev/null 2>&1; sort -u "$tmp/tool.log")"

# --uninstall removes the link and the data, nothing else.
: >"$HOME/.local/bin/keep"
check "--uninstall exits 0" "0" "$(install --uninstall)"
check "it removes the link and the data" "0 0" "$(printf '%s %s' "$([ -e "$HOME/.local/bin/crew" ] && echo 1 || echo 0)" "$([ -e "$data" ] && echo 1 || echo 0)")"
check "and nothing else" "1" "$([ -e "$HOME/.local/bin/keep" ] && echo 1)"
check "--uninstall with nothing installed" "0" "$(install --uninstall)"

# crew version and crew update, on an install and on a checkout.
install --version v1.0.0 >/dev/null
home_was=$CREW_HOME
CREW_HOME=$data/v1.0.0
check "version of an install" "crew v1.0.0" "$(crew_version)"
check "update --check names both" "crew v1.0.0; the latest release is v1.1.0" "$(crew_update --check | sed -n 1p)"
check "update --check installs nothing" "v1.0.0" "$(readlink "$data/current")"
check "update installs the latest" "v1.1.0" "$(crew_update >/dev/null; readlink "$data/current")"
check "and keeps the link where it was" "$HOME/.local/bin/crew" "$(cat "$data/link")"
CREW_HOME=$data/v1.1.0
check "update says when up to date" "up to date" "$(crew_update | sed -n 2p)"
check "update takes --check only" "2" "$(crew_update --now >/dev/null 2>&1; echo $?)"
git clone -q --branch v1.0.0 "$tmp/src" "$tmp/checkout" 2>/dev/null
CREW_HOME=$tmp/checkout
check "version of a checkout at a tag" "1" "$(crew_version | grep -c '^crew v1.0.0 (20[0-9-]*)$')"
check "a checkout is not replaced" "1" "$(crew_update >/dev/null 2>&1; echo $?)"
check "and is told to pull" "1" "$(crew_update 2>&1 | grep -c 'git pull')"
CREW_HOME=$home_was
printf '#!/bin/sh\nexit 22\n' >"$tmp/bin/curl"
check "update with no release to read" "1" "$(crew_update --check >/dev/null 2>&1; echo $?)"


# What a stranger's machine needs: a crew of someone else at the prefix is
# left alone, a version that is not one is refused before any download, a
# download cut short runs nothing, and crew update runs only the release's
# own install.sh.
install --uninstall >/dev/null
ln -s /usr/bin/true "$HOME/.local/bin/crew"
check "another crew at the prefix stops the install" "1" "$(install)"
check "and is named, with --prefix as the way out" "1" "$(grep -c "^install: $HOME/.local/bin/crew is there already and is not this install's link (it is /usr/bin/true): --prefix <dir> links elsewhere; nothing installed$" "$tmp/install.out")"
check "and nothing is downloaded or installed" "0" "$([ -e "$data" ] && echo 1 || echo 0)"
check "and the other crew stays" "/usr/bin/true" "$(readlink "$HOME/.local/bin/crew")"
rm "$HOME/.local/bin/crew"
: >"$tmp/fetched"
cat >"$tmp/bin/curl" <<EOF
#!/bin/sh
out=""
url=""
while [ \$# -gt 0 ]; do
    case "\$1" in
    -o) out=\$2; shift ;;
    -*) ;;
    *) url=\$1 ;;
    esac
    shift
done
echo "\$url" >>"$tmp/fetched"
cp "$fake/\${url#$CREW_RELEASES/}" "\$out"
EOF
check "a version with a slash is refused" "1" "$(install --version 'v1/../x')"
check "a version with a space is refused" "1" "$(install --version 'v1 x')"
check "a version that is not one is refused" "1" "$(install --version 1.0.0)"
check "before any download" "0" "$(wc -l <"$tmp/fetched" | tr -d ' ')"
check "and the message says what a version is" "1" "$(grep -c "^install: '1.0.0' is not a version like v1.0.0: nothing installed$" "$tmp/install.out")"
cp "$fake/latest/download/SHA256SUMS" "$tmp/sums.good"
sed 's/crew-v1\.1\.0\.tar\.gz/crew-v1.1.0\/..\/x.tar.gz/' "$tmp/sums.good" >"$fake/latest/download/SHA256SUMS"
check "a SHA256SUMS naming no version installs nothing" "1" "$(install)"
check "and update reads no latest from it" "1" "$(crew_update --check >/dev/null 2>&1; echo $?)"
cp "$tmp/sums.good" "$fake/latest/download/SHA256SUMS"
check "a script cut short runs nothing" "0" "$(sed '$d' "$CREW_HOME/install.sh" | sh >/dev/null 2>&1; echo $?)"
check "and installs nothing" "0" "$([ -e "$data" ] && echo 1 || echo 0)"
install --version v1.0.0 >/dev/null
CREW_HOME=$data/v1.0.0
printf '#!/bin/sh\necho tampered\n' >"$fake/download/v1.1.0/install.sh"
check "update refuses an install.sh that is not the release's" "1" "$(crew_update >/dev/null 2>&1; echo $?)"
check "and says so" "1" "$(crew_update 2>&1 | grep -c "^crew: v1.1.0's install.sh does not match its SHA256SUMS: not run$")"
check "and the install stays" "v1.0.0" "$(readlink "$data/current")"
CREW_HOME=$home_was


# A checkout that holds a VERSION file is still a checkout: its .git says so,
# crew version reads the tag from git, and crew update sends it to git pull.
printf 'v1.0.0\n' >"$tmp/checkout/VERSION"
CREW_HOME=$tmp/checkout
check "a checkout with a VERSION file is a checkout to crew version" "1" "$(crew_version | grep -c '^crew v1.0.0 (20[0-9-]*)$')"
check "and to crew update" "1" "$(crew_update >/dev/null 2>&1; echo $?)"
check "which installs nothing" "v1.0.0" "$(readlink "$data/current")"
CREW_HOME=$home_was

finish
