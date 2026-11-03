<!-- What changes and why, as a commit body says it. Closes #<n> when it closes an issue. -->

- [ ] `sh test/run.sh`, `sh -n`, and `shellcheck` pass, as CONTRIBUTING.md runs them
- [ ] No new dependency beyond POSIX `sh`, `awk`, `sed`, `osascript`, and `tmux`
- [ ] A change to what agents must do updates `share/protocol.md`
- [ ] A change to the gate's rules updates the table in `test/gate_test.sh`
- [ ] A new prompt format comes with a fixture from the real agent (`crew peek <name> 40`) and a line in `test/fixtures/VERSIONS`
