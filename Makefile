HCC ?= hcc

.PHONY: all build test clean

all: build

build:
	$(HCC) src/ide.HC -o wside

test:
	$(HCC) src/tests.HC -o tests
	./tests

clean:
	rm -f wside tests
