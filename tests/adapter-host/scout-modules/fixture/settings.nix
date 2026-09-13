{ config, ... }:
{
  enable = true;
  output = "flakelets.default";
  settings.nixos.services.fixture.enable = true;
  settings.homeManager.programs.fixture.message =
    if config.users.users.fixture.isNormalUser then "host-resolved" else "wrong-context";
  autoUpdate.enable = false;
}
