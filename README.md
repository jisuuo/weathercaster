# weathercaster

## Simulator checks

```bash
bash scripts/sim-verify.sh   # cold boot -> Metro -> Expo Go -> bundle + screenshot
bash scripts/sim-e2e.sh      # the above, then the Maestro flows in .maestro/
```

`sim-e2e.sh` needs Maestro at `~/.maestro/bin/maestro`. Homebrew refuses to install it
until the Command Line Tools are updated, so it is unpacked from the archive Homebrew
already downloads:

```bash
brew tap mobile-dev-inc/tap
brew fetch mobile-dev-inc/tap/maestro
unzip -q "$(brew --cache mobile-dev-inc/tap/maestro)" -d /tmp/maestro-dl
mv /tmp/maestro-dl/maestro ~/.maestro
```
