# nene
`nene` is a small utility to automate downloading torrents of series over RSS.
It is much faster than alternatives like [flexget](https://flexget.com/), due to being written in a compiled language and running several tasks concurrently.

## Building
`nene` requires **OCaml** and **opam** to be built, and **curl** and **transmission-daemon** with its client **transmission-remote** to be used. Support for more downloaders and torrent clients will be configurable in a separate config file at a later date.

To install the dependencies and build:
```
opam install xml-light sexplib lwt
make
```

## Usage
To fetch shows, simply call it with no arguments.

```
$ nene
```

`nene` requires a shows file, by default called `shows.scm`, defining the series and the RSS urls to fetch them from.

`nene` makes use of the XDG base directory `XDG_CONFIG_DIR`, which can be defined by the environment variable of the same name and defaults to `$HOME/.config`. The default position of the `shows.scm` file is inside that directory, but you can change it by passing it as a command line option:

```
$ nene -shows /path/to/shows-file.scm
```

The default download directory is `$HOME/vid/airing` because that's where I keep my airing shows, but it can be changed by passing `-download-dir`. At this time, the default download directory can only be changed at compile time.

```
$ nene -download-dir path/to/download/dir
```

`nene` doesn't and won't run as a daemon; your OS most likely has one or a few perfectly good systems to run tasks periodically. If you have `cron(8)` running, you can add this line to your crontab file to run `nene` every 15 minutes:

```
0/15 * * * * /path/to/nene -download-dir /path/to/download/dir
```

Refer to the `cron` and `crontab` manpages for more information.

### Shows file
This is an example shows file:
```Scheme
(https://nyaa.si/?page=rss&q=kirakira+precure+anon&c=0_0&f=0
  (("KiraKira Precure À La Mode"
    "\\[anon\\] KiraKira Precure À La Mode - \\([0-9][0-9]\\)\\(v[0-9]\\)? \\[1280x720\\( 8bit\\)?\\]\\.mkv")))

(https://horriblesubs.info/rss.php?res=720
  (("Sakura Quest"
    "\\[HorribleSubs\\] Sakura Quest - \\([0-9][0-9]\\)\\(v[0-9]\\)? \\[720p\\]\\.mkv")

   ("Centaur no Nayami"
    "\\[HorribleSubs\\] Centaur no Nayami - \\([0-9][0-9]\\)\\(v[0-9]\\)? \\[720p\\]\\.mkv")

   ("Mahoujin Guru Guru"
    "\\[HorribleSubs\\] Mahoujin Guru Guru (2017) - \\([0-9][0-9]\\)\\(v[0-9]\\)? \\[720p\\]\\.mkv")))
```

The file should follow the schema `(<rss url> ((<show name> <show regexp>) ...)) ...`. Strings with spaces or parenthesis in them should always be double quoted.

The regexp strings follow the same quoting rules as OCaml's [Str module](https://caml.inria.fr/pub/docs/manual-ocaml-4.05/libref/Str.html), and the first and second match groups should be respectively the episode number and its version. I opted for this instead of tyring to automatically parse filenames, because automatically parsing filenames is impossible, and I dare you to come up with a consistent way of parsing them if you don't think this is the case.

Seeing as most filenames have a few recurring parts, this could be replaced by some manner of specifying where the episode number and version are without having to quote everything.

## Known issues
- Many things are not configurable at runtime.
- It depends on curl and transmission-remote. I'd like to use a pure OCaml library to replace them.
- It doesn't check whether adding the torrent to Transmission has succeeded.
- There might be a few uncaught exceptions that should have been caught.
- Generally, the program should work by having a tree of transactions that abort gracefully. Right now it doesn't work nearly as consistently.
- It accepts any command line argument you throw at it.
