OPAM_EXEC = opam exec --
DUNE = $(OPAM_EXEC) dune

.PHONY: deps build test test-gnu test-system test-js fuzz fmt fmt-check ci clean

deps:
	opam install . --deps-only --with-test -y

build:
	$(DUNE) build @all

test:
	$(DUNE) build @runtest

# Tests that need cross binutils or QEMU. A missing tool prints SKIP unless
# ELF_REQUIRE_TOOLCHAIN=1.
test-gnu:
	$(DUNE) build @test-gnu

test-system:
	$(DUNE) build @test-system

test-js:
	$(DUNE) build @test-js

fuzz:
	ELF_FUZZ_N=100000 $(DUNE) exec test/unit/test_fuzz.exe

fmt:
	$(DUNE) build @fmt --auto-promote

fmt-check:
	$(DUNE) build @fmt

ci: fmt-check build test

clean:
	$(DUNE) clean
