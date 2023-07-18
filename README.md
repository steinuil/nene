# nene

A small utility to automate downloading torrents of ongoing series via RSS.

## Config file

Nene is controlled through a JSON config file specifying the downloader, the trackers, and the shows to be found on these trackers.

The downloader can be one either:

- A directory, specified with the `directory` key and the path to the directory as value.

  ```json
  {
    "backend": {
      "directory": "/path/to/directory"
    },
    "trackers": ...
  }
  ```

- Transmission, specified with the `transmission` key as an object containing the url of the RPC
  and the directory that the torrent files will be downloaded into.
  ```json
  {
    "backend": {
      "transmission": {
        "host": "http://localhost:9091/transmission/rpc",
        "download_dir": "/var/transmission/shows"
      }
    },
    "trackers": ...
  }
  ```

To recognize the episode name, two mechanisms can be used:

- If the episode number is in the format `\d+(v\d)?` (e.g. `2`, `52v2`), a pattern can be defined by taking the
  episode name and replacing the number with `<episode>`. A glob `**` can also be used to ignore parts of the
  filename like the CRC32 hash or other details that may vary from file to file.
  For example, the pattern `[Commie] SSSS.GRIDMAN - <episode> [**].mkv` will match the episode name
  `[Commie] SSSS.GRIDMAN - 07 [15CCEA4B].mkv` with number = 7 and version = 1.

- For more complex cases, Perl-compatible regular expressions (PCRE) can be used by specifying in an object
  the expression, the index of the group containing the episode, and the index of the group containing the version.

Here's a full example of a config file.

```json
{
  "backend": {
    "transmission": {
      "host": "http://localhost:9091/transmission/rpc",
      "download_dir": "/var/transmission/shows"
    }
  },
  "trackers": [
    {
      "url": "https://example.com/rss",
      "shows": [
        {
          "name": "SSSS.GRIDMAN",
          "pattern": "[Commie] SSSS.GRIDMAN - <episode> [**].mkv"
        },
        {
          "name": "Mewkledreamy",
          "regexp": {
            "pattern": "Mewkledreamy - (\\d+) \\[v(\\d+)\\]",
            "episode": 1,
            "version": 2
          }
        }
      ]
    }
  ]
}
```

## Installation and usage with NixOS

This repository provides a flake containing the `nene` package and a NixOS module for
easy installation and setup on NixOS. Here is an example configuration:

### flake.nix

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    nene = {
      url = "github:steinuil/nene";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, nene }: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nene.nixosModules.x86_64-linux
        ./configuration.nix
      ];
    };
  };
}
```

### configuration.nix

```nix
{ pkgs, lib, ... }:
{
  # ...

  services.transmission = {
    enable = true;
    settings.download-dir = "/mnt/external";
    # ...
  };

  services.nene = {
    enable = true;
    after = [ "transmission.service" ];
    timerInterval = "15m";
    settings = {
      backend.transmission = {
        host = "http://localhost:9091/transmission/rpc";
        download_dir = "/mnt/external/Anime";
      };
      trackers = [
        {
          url = "https://example.com/rss";
          shows = [
            {
              name = "SSSS.GRIDMAN";
              pattern = "[Commie] SSSS.GRIDMAN - <episode> [**].mkv";
            }
            {
              name = "Mewkledreamy";
              regexp = {
                pattern = "Mewkledreamy - (\\d+) \\[v(\\d+)\\]";
                episode = 1;
                version = 2;
              };
            }
          ]
        }
      ];
    };
  };
}
```

This will install a systemd service and a systemd timer that will run `nene` every 15 minutes
and send the torrents to a Transmission instance running locally.
