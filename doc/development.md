## Development environment

The reference toolchain is pinned in `flake.nix` and `flake.lock`:

- Ruby 4.0.7, the latest stable release
- Bundler, OpenSSL bindings, `pkg-config`, `jq` and `git`

Enter it with `nix develop`. Gems resolve into `.nix/gems` through
`GEM_HOME`/`BUNDLE_PATH`, so the host's Ruby and global gem directory are never
used:

```sh
nix develop -c bundle install
nix develop -c bundle exec rake
```

The canonical development machine is macOS on Apple silicon. Continuous
integration is out of scope: the host is the reference environment.

### Without Nix

Ruby 4.0 with an isolated `BUNDLE_PATH` works:

```sh
bundle config set --local path .bundle/gems
bundle install
bundle exec rake
```

That path is supported but is not the reference environment.
