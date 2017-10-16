all: nene.native

nene.native:
	ocamlbuild -use-ocamlfind nene.native

clean:
	ocamlbuild -clean

install-deps:
	opam install xml-light sexplib cohttp-lwt-unix yojson

.PHONY: nene.native clean deps
