(lang dune 2.0)

(name nene)

(version 1.0)

(license "MIT")

(generate_opam_files true)

(source
 (github steinuil/nene))

(package
 (name nene)
 (synopsis "")
 (description "")
 (depends sexplib cohttp-lwt-unix lwt_ssl yojson xmlm patche re cmdliner))
