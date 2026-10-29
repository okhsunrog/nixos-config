{ config, lib, ... }:
{
  options.framework.plasmaLoginAuth.enable =
    lib.mkEnableOption "password-only Plasma greeter authentication"
    // {
      default = config.services.displayManager.plasma-login-manager.enable;
    };
  config = lib.mkIf config.framework.plasmaLoginAuth.enable {
    # Change only the greeter's auth substack. Its account/password/session stacks
    # still use login. Fingerprints are reserved for unlocking an existing session.
    security.pam.services.plasmalogin.rules.auth.login.modulePath = lib.mkForce "plasmalogin-auth";
    security.pam.services.plasmalogin-auth = {
      kwallet.enable = config.security.pam.services.login.kwallet.enable;
      fprintAuth = false;
      allowNullPassword = false;
    };
    # KDE runs password and fingerprint authentication independently. Keep the
    # fingerprint worker from falling through to another password conversation.
    security.pam.services.kde-fingerprint.unixAuth = false;
  };
}
