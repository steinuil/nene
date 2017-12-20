PROJECT = nene
DEPS = ocamlfind jbuilder cohttp-lwt-unix sexplib xml-light yojson

all:
	jbuilder build -p $(PROJECT)
.PHONY: all

clean:
	jbuilder clean
.PHONY: clean

install: all
	jbuilder install -p $(PROJECT)
.PHONY: install

uninstall:
	jbuilder uninstall -p $(PROJECT)
.PHONY: uninstall

install-deps:
	opam install $(DEPS)
# opam install --deps-only .
.PHONY: install-deps
