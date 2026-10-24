{ ... }:
{
  imports = [ ../../modules/framework-environments ];
  framework.environments = {
    enable = true;
    user = "okhsunrog";
    uid = 1000;
    gid = 1000;
    entries = {
      kde = {
        dataset = "novafs/nixos0/data/home";
        backup = "mira";
      };
      niri = {
        # Prepared from the primary home snapshot; keep independent user state.
        enable = true;
        dataset = "novafs/nixos0/data/home-niri";
        backup = "local";
      };
    };
    variants.niri = ./desktops/niri.nix;
  };
}
