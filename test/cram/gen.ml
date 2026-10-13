[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

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
  | Error e -> Format.printf "%a@." (Err.Error.pp_kind Encode.pp_error) e

let write path data =
  let oc = open_out_bin path in
  output_string oc data;
  close_out oc

let riscv_attributes () =
  let attrs =
    [
      {
        Attributes.vendor = "riscv";
        contents =
          `Parsed
            [
              ( Attributes.File,
                [ (4, Attributes.Uleb 16L); (5, Ntbs "rv32i2p0_m2p0"); (6, Uleb 1L) ] );
            ];
      };
      { vendor = "other"; contents = `Raw "\001\002" };
    ]
  in
  match Attributes.encode Little attrs with
  | Ok data ->
      Elf_test_support.Fixture.build Elf32 Little
        [ Elf_test_support.Fixture.sect ".riscv.attributes" Const.sht_riscv_attributes data ]
  | Error _ -> failwith "attributes"

let () =
  match Array.to_list Sys.argv with
  | [ _; "encode-overflow" ] -> encode_overflow ()
  | [ _; "minimal-elf32-le"; path ] -> write path (Elf_test_support.Fixture.minimal ())
  | [ _; "minimal-elf64-be"; path ] ->
      write path (Elf_test_support.Fixture.minimal ~cls:Elf64 ~endian:Big ())
  | [ _; "riscv-attributes"; path ] -> write path (riscv_attributes ())
  | [ _; "many-sections"; path ] -> write path (Elf_test_support.Fixture.many_sections 0xff0e)
  | [ _; "bad-magic"; path ] ->
      write path (Elf_test_support.Fixture.minimal () |> Elf_test_support.Fixture.set_u8 0 0)
  | [ _; "truncated"; path ] ->
      write path (Elf_test_support.Fixture.minimal () |> Elf_test_support.Fixture.truncate 30)
  | _ ->
      prerr_endline "usage: gen <case> [FILE]";
      exit 2
