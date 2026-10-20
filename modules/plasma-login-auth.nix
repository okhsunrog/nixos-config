{ config, lib, ... }:
{
  # Change only the greeter's auth substack. Its account/password/session stacks
  # still use login; KDE's separate screen-lock PAM services remain untouched.
  security.pam.services.plasmalogin.rules.auth.login.modulePath = lib.mkForce "plasmalogin-auth";
  security.pam.services.plasmalogin-auth = {
    kwallet.enable = config.security.pam.services.login.kwallet.enable;
    # A successful password must finish before a fingerprint is requested.
    # A blank or incorrect password may fall through to fingerprint auth.
    rules.auth.fprintd.order = config.security.pam.services.plasmalogin-auth.rules.auth.unix.order + 10;
  };
}
