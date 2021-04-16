# nene

A small utility to automate downloading torrents of ongoing series via RSS.

## Config file

Nene is controlled through a JSON config file specifying the downloader (currently only transmission is available),
the trackers, and the shows to be found on these trackers.

To recognize the episode name, two mechanisms can be used:

- If the episode number is in the format `\d+(v\d)?` (e.g. `2`, `52v2`), a pattern can be defined by taking the
  episode name and replacing the number with `<episode>`. A glob `**` can also be used to ignore parts of the
  filename like the CRC32 hash or other details that may vary from file to file.
  For example, the pattern `[Commie] SSSS.GRIDMAN - <episode> [**].mkv` will match the episode name
  `[Commie] SSSS.GRIDMAN - 07 [15CCEA4B].mkv` with number = 7 and version = 1.

- For more complex cases, Perl-compatible regular expressions (PCRE) can be used by specifying in an object
  the expression, the index of the group containing the episode, and the index of the group containing the version.

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
