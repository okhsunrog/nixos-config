# AyuGram with PLEngine

`hosts/framework/ayugram-plengine.nix` replaces the normal AyuGram package with
the pinned `linux-plengine-7.2` branch of
`github:okhsunrog/AyuGramDesktop-PLEngine`. The baseline is official AyuGram
7.2.9; the old fork remains available as `linux-plengine-6.7.5`.

The source flake reuses Nixpkgs' native client build and Qt wrapper. It builds
the channel reader and smoke plugin in the same derivation, against the same
generated protocol headers and C++ toolchain. Native plugin binaries from the
old Arch build are not reused.

User tmpfiles link the two packaged `.so` files into
`~/.local/share/AyuGramDesktop/plugins/`. Configuration, feed output, login
sessions and other mutable user data remain in their existing locations.
The package does not enable the optional PLEngine HTTP API.

To update, first build and validate the source branch, then update just this
input with `nix flake update ayugram-plengine` and use the normal
`framework-rebuild` workflow. The client and its packaged plugins must move
together; do not replace only one plugin with a binary from another build.

Validation uses a separate empty profile and a disabled reader configuration,
so it does not open or alter the personal Telegram session. It checks plugin
loading with immediate symbol resolution, main-thread queue dispatch, reader
status generation and clean exit. Authenticated channel polling and interactive
message/context-menu hooks require acceptance in the real user session.
