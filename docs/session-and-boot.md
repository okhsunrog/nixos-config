# Desktop wallet and default boot environment

## Password and fingerprint login

`modules/plasma-login-auth.nix` gives Plasma Login Manager its own auth substack.
A correct account password finishes authentication before the fingerprint
module. Blank or incorrect password input falls through to the fingerprint
alternative; failure of both is rejected. The upstream account, password-change
and session stacks still use `login`.

This changes the greeter only. The screen lock uses its existing `kde` and
`kde-fingerprint` PAM services; neither those nor the generic console `login`
stack is modified. KWallet is independent of this choice of login method.

`nix build .#checks.x86_64-linux.plasma-login-auth` verifies the generated PAM
stack in a disposable VM. It uses real password verification for a test account
and a simulated fingerprint result, without accessing host credentials or the
physical reader. Physical greeter interaction still requires a subsequent login.

On 2026-10-20 the VM test passed all four cases, including the real optional
KWallet PAM hook. The host configuration was built and activated. SHA-256 checks
confirmed that `kde`, `kde-fingerprint` and console `login` were unchanged after
activation. Plasma Login Manager, Floppa and Arctern retained their process IDs;
the desktop session was not restarted.

## KWallet

The owner selected an empty password for the existing `kdewallet` on
2026-10-19, retaining fingerprint login without a separate wallet password.
The password was changed through KWallet's own change-password dialog while
the wallet was already unlocked. No entries were exported or read, and wallet
support remains enabled. The wallet file retains mode 0600 in the user's home.

This removes the wallet's separate password protection. At-rest protection comes
from native ZFS encryption and file permissions. The wallet is mutable personal
state under `~/.local/share/kwalletd`, not a Nix-store object or Git input. A Nix
activation must not recreate it or overwrite its contents.

Before the change, fingerprint authentication left PAM without a wallet key:
`open_session called without kwallet5_key`. Password-based PAM wallet unlocking
cannot derive a decryption key from a successful fingerprint check alone.

The dialog completed and the wallet remained open. A non-forced test close was
declined because applications were using it; no clients were disconnected.
Prompt-free opening after the next desktop login still requires confirmation.

## Default operating system in zbm-rs

The pool property is now `bootfs=novafs/nixos0/root` on `novafs`; its previous
value was unset. The owner explicitly selected NixOS as the default and retained
Arch as a fallback. The running NixOS root was verified unlocked and bootable
from the current session before setting the property.

zbm-rs reads `bootfs` as the preferred boot environment and places it first with
the selection highlighted. Automatic-boot policy is a separate image setting;
no menu/countdown/immediate policy or EFI firmware order was changed here.
The property is persistent pool metadata and needs no image rebuild or signing.
The next physical boot still has to confirm the visible selection.
