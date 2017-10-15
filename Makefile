nene.native:
	ocamlbuild -use-ocamlfind nene.native

clean:
	ocamlbuild -clean

deps:
	opam install xml-light sexplib cohttp-lwt-unix yojson
