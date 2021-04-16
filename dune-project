(lang dune 2.8)

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
 (depends
  (cohttp-lwt-unix
   (>= 4.0.0))
  (cmdliner
   (>= 1.0.4))
  (sexplib
   (>= 0.14.0))
  (lwt_ssl
   (>= 1.1.3))
  (yojson
   (>= 1.7.0))
  (xmlm
   (>= 1.3.0))
  (re
   (>= 1.9.0))
  (lwt_ppx
   (>= 2.0.1))
  (ppx_inline_test
   (>= 0.14.1))))
