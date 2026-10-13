[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

(* README.md's example has already run (Readme_example is linked first) and written ./hello. *)

open Elf_test_support
open Elf

let () = assert Readme_example.ran

let () =
  Check.run "readme"
    [
      Check.case "the example's output is a valid RV32 executable" (fun () ->
          let bytes = Check.ok ~pp_error:Elf_unix.pp_error "read" (Elf_unix.read_file "hello") in
          let d = Check.ok ~pp_error:Decode.pp_error "decode" (Decode.of_string bytes) in
          Check.equal ~pp:Format.pp_print_int "machine" Const.em_riscv d.header.e_machine;
          Check.equal
            ~pp:(fun ppf v -> Format.fprintf ppf "0x%Lx" v)
            "entry" 0x10000L d.header.e_entry;
          Check.equal ~pp:Format.pp_print_string "code"
            "\x13\x05\xa0\x02\x93\x08\xd0\x05\x73\x00\x00\x00"
            (Check.ok ~pp_error:Decode.pp_error "text"
               (Decode.section_data d (Option.get (Decode.find_section d ".text"))));
          Check.equal ~pp:Format.pp_print_int "executable bit" 0o755 (Unix.stat "hello").st_perm);
    ]
