all:
	ocamlbuild -use-ocamlfind nene.native

deps:
	opam install xml-light sexplib
