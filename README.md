# `zignix`

Zig bindings to the Nix package manager.

Built based on the latest stable Nix version (2.33.1 at time of writing).

Documentation for the raw C API these bindings is based off of is available from
the [Hydra](https://hydra.nixos.org/build/316133169/download/1/html/) cache.

You can find the link for these docs by going to https://hydra.nixos.org,
looking for the Nix job set, and searching for `external-api-docs` in the built
artifacts.

This repository is hosted on [sr.ht](sr.ht/~watersucks/optnix), with an official
mirror on [GitHub](https://github.com/water-sucks/optnix).

## Contributing

Prefer emailing patch sets to the
[official development mailing list](mailto:~watersucks/zignix-devel@lists.sr.ht).

While the official repository is located on
[sr.ht](https://git.sr.ht/~watersucks/zignix), contributions are also accepted
through GitHub using the
[official mirror](https://github.com/water-sucks/zignix), if desired.

Additionally, filing GitHub issues is fine, but consider using the official
issue tracker on [sr.ht](https://todo.sr.ht/~watersucks/zignix). All issues from
GitHub will be mirrored there by me anyway.

## TODO

- [ ] External values
- [ ] `PrimOp` support
