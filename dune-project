(lang dune 3.15)

(name elf)

(generate_opam_files true)

(license MIT)

(authors "Vladimir Silyaev")

(maintainers "Vladimir Silyaev")

(source
 (github TheCBaH/ocaml-elf))

(package
 (name elf)
 (synopsis "Pure-OCaml ELF32/ELF64 reader and static executable writer")
 (description
  "Checked ELF32/ELF64 codecs, bounded parsing, and static ET_EXEC generation for x86-32, x86-64, ARM, AArch64, RV32 and RV64. The core library depends only on the OCaml standard library and err_trace.")
 (depends
  (ocaml
   (>= 4.14))
  (dune
   (>= 3.15))
  (err_trace
   (= dev))))
