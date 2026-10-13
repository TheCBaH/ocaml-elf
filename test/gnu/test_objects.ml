(* Decode GNU-assembled relocatable objects and compare the result with readelf. *)

open Elf_test_support
open Elf
module R = Elf_test_support.Readelf
module T = Elf_gnu.Toolchain

let ok what r = Check.ok ~pp_error:Decode.pp_error what r

module C = Readelf_check

(* .text with a global and a local function (the local one calls an undefined symbol), .data with a
   word that refers to .text (so it needs a relocation), and a zero-filled .bss. *)
let source (arch : Target.arch) =
  match arch with
  | Riscv32 | Riscv64 ->
      let word = if arch = Riscv32 then ".word" else ".dword" in
      String.concat "\n"
        [
          "\t.option norelax";
          "\t.text";
          "\t.globl gfn";
          "\t.type gfn,@function";
          "gfn:\tnop";
          "\tret";
          "\t.type lfn,@function";
          "lfn:\tcall ext";
          "\t.data";
          "\t.globl dat";
          "dat:\t" ^ word ^ " lfn";
          "\t.bss";
          "\t.zero 64";
          "";
        ]
  | X86_32 | X86_64 ->
      let word = if arch = X86_32 then ".long" else ".quad" in
      String.concat "\n"
        [
          "\t.text";
          "\t.globl gfn";
          "\t.type gfn,@function";
          "gfn:\tnop";
          "\tret";
          "\t.type lfn,@function";
          "lfn:\tcall ext";
          "\t.data";
          "\t.globl dat";
          "dat:\t" ^ word ^ " lfn";
          "\t.bss";
          "\t.zero 64";
          "";
        ]
  | Arm ->
      String.concat "\n"
        [
          "\t.arm";
          "\t.text";
          "\t.globl gfn";
          "\t.type gfn,%function";
          "gfn:\tnop";
          "\tbx lr";
          "\t.type lfn,%function";
          "lfn:\tbl ext";
          "\t.data";
          "\t.globl dat";
          "dat:\t.word lfn";
          "\t.bss";
          "\t.zero 64";
          "";
        ]
  | Aarch64 ->
      String.concat "\n"
        [
          "\t.text";
          "\t.globl gfn";
          "\t.type gfn,%function";
          "gfn:\tnop";
          "\tret";
          "\t.type lfn,%function";
          "lfn:\tbl ext";
          "\t.data";
          "\t.globl dat";
          "dat:\t.xword lfn";
          "\t.bss";
          "\t.zero 64";
          "";
        ]

let write path data =
  let oc = open_out_bin path in
  output_string oc data;
  close_out oc

let test_arch (arch : Target.arch) =
  let name = Format.asprintf "%a" Target.pp_arch arch in
  match T.find arch with
  | Error (`Missing tool) -> T.skip_or_fail tool
  | Ok tools -> (
      let dir = T.artifacts ("objects-" ^ name) in
      let src = Filename.concat dir "payload.s" and obj = Filename.concat dir "payload.o" in
      write src (source arch);
      let status, _, err = T.run (tools.as_ @ [ src; "-o"; obj ]) in
      if status <> 0 then Check.failf "%s: assembler failed: %s" name err;
      let data = Check.ok ~pp_error:Elf_unix.pp_error "read" (Elf_unix.read_file obj) in
      let d = ok "decode" (Decode.of_string data) in
      let readelf flag =
        let status, out, err = T.run [ tools.readelf; "-W"; flag; obj ] in
        if status <> 0 then Check.failf "%s: readelf %s failed: %s" name flag err;
        out
      in
      C.mismatches := [];
      C.check_sections arch d (readelf "-S");
      C.check_symbols d (readelf "-s");
      C.check_relocs d (readelf "-r");
      C.check_attributes arch d (readelf "-A");
      (* The object has relocations for .data, and the code uses a symbol this file does not define. *)
      match !C.mismatches with
      | [] -> ()
      | l -> Check.failf "\n  %s" (String.concat "\n  " (List.rev l)))

(* An object with more than SHN_LORESERVE sections: GAS uses extended numbering (e_shnum = 0 and
   e_shstrndx = SHN_XINDEX, with the real values in section header 0). *)
let test_extended_numbering () =
  match T.find Target.X86_64 with
  | Error (`Missing tool) -> T.skip_or_fail tool
  | Ok tools -> (
      let dir = T.artifacts "objects-extended" in
      let src = Filename.concat dir "many.s" and obj = Filename.concat dir "many.o" in
      let b = Buffer.create (1 lsl 20) in
      for i = 0 to 65_299 do
        Buffer.add_string b (Printf.sprintf "\t.section s%d,\"a\"\n\t.byte %d\n" i (i land 0xff))
      done;
      write src (Buffer.contents b);
      let status, _, err = T.run (tools.as_ @ [ src; "-o"; obj ]) in
      if status <> 0 then Check.failf "assembler failed: %s" err;
      let data = Check.ok ~pp_error:Elf_unix.pp_error "read" (Elf_unix.read_file obj) in
      let h = Fixture.header data in
      Check.equal ~pp:Format.pp_print_int "e_shnum is 0" 0 h.e_shnum;
      Check.equal ~pp:Format.pp_print_int "e_shstrndx is SHN_XINDEX" Const.shn_xindex h.e_shstrndx;
      let d = ok "decode" (Decode.of_string data) in
      if d.shnum < Const.shn_loreserve then Check.failf "only %d sections" d.shnum;
      let status, out, err = T.run [ tools.readelf; "-W"; "-S"; obj ] in
      if status <> 0 then Check.failf "readelf failed: %s" err;
      C.mismatches := [];
      C.check_sections Target.X86_64 d out;
      match !C.mismatches with
      | [] -> ()
      | l ->
          Check.failf "\n  %s"
            (String.concat "\n  " (List.filteri (fun i _ -> i < 20) (List.rev l))))

let () =
  Check.run "objects"
    (List.map
       (fun arch ->
         Check.case (Format.asprintf "%a" Target.pp_arch arch) (fun () -> test_arch arch))
       Target.all
    @ [ Check.case "extended section numbering (GAS, 65300 sections)" test_extended_numbering ])
