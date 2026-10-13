(* Test input generator for the cram suites: `gen.exe <case> [FILE]`. *)

open Elf
open Types

let () = Err.Config.set Err.Config.deterministic

let encode_overflow () =
  let id = { elf_class = Elf32; endianness = Little; osabi = 0; abiversion = 0 } in
  let p =
    {
      p_type = 1L;
      p_flags = 5L;
      p_offset = 0L;
      p_vaddr = 0x1_0000_0000L;
      p_paddr = 0L;
      p_filesz = 0L;
      p_memsz = 0L;
      p_align = 0x1000L;
    }
  in
  match Encode.write_phdr id (Bytes.create 32) 0 ~index:3 p with
  | Ok () -> print_endline "unexpected success"
  | Error e -> Format.printf "%a@." (Err.Error.pp Encode.pp_error) e

let () =
  match Array.to_list Sys.argv with
  | [ _; "encode-overflow" ] -> encode_overflow ()
  | _ ->
      prerr_endline "usage: gen <case> [FILE]";
      exit 2
