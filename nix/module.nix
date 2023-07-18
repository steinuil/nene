{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.nene;

  configFile = pkgs.writeText "nene-config.json" (builtins.toJSON cfg.settings);
in
{
  options.services.nene = {
    enable = mkEnableOption "nene";

    package = mkPackageOptionMD pkgs "nene" { };

    after = mkOption {
      description = "List of systemd services that should be online before starting the timer";
      type = types.listOf types.str;
      default = [ "transmission.service" ];
    };

    timerInterval = mkOption {
      description = "systemd.timer(5) time unit specifying how often nene should run";
      type = types.str;
      default = "15m";
    };

    settings = with types; mkOption {
      type = submodule {
        options.backend = mkOption {
          type = either
            (submodule {
              options.transmission = mkOption {
                description = "Send torrents to Transmission RPC";
                type = submodule {
                  options.host = mkOption {
                    type = str;
                    description = "RPC URL to Transmission";
                    example = "http://localhost:9091/transmission/rpc";
                  };
                  options.download_dir = mkOption {
                    type = nullOr path;
                    description = "The directory Transmission should download the torrent to";
                    example = "/mnt/external/torrents";
                  };
                };
              };
            })
            (submodule {
              options.directory = mkOption {
                description = "Download .torrent files to a directory";
                type = path;
              };
            });
        };
        options.trackers = mkOption {
          type = listOf (submodule {
            options.url = mkOption {
              description = "URL of the RSS feed";
              type = str;
            };
            options.shows = mkOption {
              description = "List of shows to download from this feed";
              type = listOf (either
                (submodule {
                  options.name = mkOption {
                    type = str;
                    description = "Name of the show";
                  };
                  options.pattern = mkOption {
                    type = str;
                    description = "Pattern to match the filename with, see https://github.com/steinuil/nene/blob/master/README.md for documentation";
                    example = "[Commie] SSSS.GRIDMAN - <episode> [**].mkv";
                  };
                })
                (submodule {
                  options.name = mkOption {
                    type = str;
                    description = "Name of the show";
                  };
                  options.regexp = mkOption {
                    type = submodule {
                      options.pattern = mkOption {
                        description = "Perl-compatible regular expression (PCRE) containing groups matching the episode name and version";
                        type = str;
                        example = "Mewkledreamy - (\\d+) \\[v(\\d+)\\]";
                      };
                      options.episode = mkOption {
                        description = "Index of the group specifying the episode number in the regular expression";
                        type = ints.positive;
                        example = 1;
                      };
                      options.version = mkOption {
                        description = "Index of the group specifying the version of the release in the regular expression";
                        type = ints.positive;
                        example = 2;
                      };
                    };
                  };
                }));
            };
          });
        };
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.services.nene = {
      script = "${cfg.package}/bin/nene --seen \"$STATE_DIRECTORY/nene.s\" ${configFile}";
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        StateDirectory = "nene";
      };
    };

    systemd.timers.nene = {
      after = [ "network-online.target" ] ++ cfg.after;
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = cfg.timerInterval;
        OnUnitActiveSec = cfg.timerInterval;
      };
    };
  };
}
