# Commands

```sh
nix flake check -L
nix fmt
nix build ".#hello-offline" ".#adapter"
```

Publish core, converge native runtime pins, and test published inputs before landing. Temporary local overrides must not be committed.
