(lang dune 2.0)

(name nene)

(version 1.0)

(license "MIT")

(generate_opam_files true)

(authors "steenuil <steen@neets.work>")

(maintainers "steenuil <steen@neets.work>")

(source
 (github steinuil/nene))

(package
 (name nene)
 (synopsis "Download torrents of ongoing series via RSS")
 (description
  "A small utility to automate downloading torrents of ongoing series updated via RSS")
 (depends sexplib cohttp-lwt-unix lwt_ssl yojson xmlm re cmdliner))
