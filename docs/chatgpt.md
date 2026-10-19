# ChatGPT desktop

`packages/chatgpt.nix` adapts the existing Nixpkgs `chatgpt` package for the
Framework host. `personal-packages.nix` installs it declaratively.

The official x86-64 Debian payload is pinned to version `26.1013.40934` and its
SHA-256. It is fetched directly from the versioned upstream URL; the local Arch
build directory and Forgejo Packages are not build inputs. Nixpkgs supplies ELF,
GTK/Qt and runtime-library fixups, desktop integration and its packaged helper
tools. The additional TPM/OpenSSL inputs satisfy the newer native device-key
module. The matching backend and code-mode host from the upstream desktop
release are retained instead of Nixpkgs' older standalone release. The separately
installed terminal package is not replaced by this adapter.

Nixpkgs' launcher creates a writable bundled-plugin copy under
`${XDG_CACHE_HOME:-$HOME/.cache}/chatgpt/bundled-plugins-v2`, because the app
rewrites plugin manifests. The application payload stays in the read-only Nix
store. Authentication and the existing user profile remain mutable home data;
they are neither imported into Nix nor overwritten during activation.

The application defaults to native Wayland when `WAYLAND_DISPLAY` is present,
matching the Arch wrapper's keyboard-layout preference. Set `NIXOS_OZONE_WL=`
for a launch without these Wayland defaults. This is an application-local
setting, not a global desktop environment variable.

To update, change the version and corresponding Debian SHA-256 in the adapter,
build the Framework configuration, and check desktop startup and bundled-plugin
loading before activation. Updates use Nix generations, not the upstream Debian
package-manager integration. An earlier system generation provides a rollback.

Upstream Linux installation documentation:
<https://learn.chatgpt.com/docs/linux/linux-app>.

## Host validation, 2026-10-19

The system was built and activated. ELF fixups resolved every dependency and
the install-time version check returned `26.1013.40934`. The KDE desktop entry
opened a native Wayland window with the existing profile and authenticated
account; the local backend reported the bundled `0.163.0-alpha.10.2` version.
The bundled-plugin cache was initialized and plugin inventory loaded. Existing
Floppa, Docker and Arctern processes were preserved.

Startup still logs `fs/readFile requires an environmentId` with both Nixpkgs'
backend and the official bundled backend, so a version mismatch is not an
established explanation for that message. It did not prevent the home screen,
account lookup or plugin inventory from loading. A new model request, every
plugin action and sandboxed project execution were not exercised.
