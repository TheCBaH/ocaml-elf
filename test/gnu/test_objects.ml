(* Decode GNU-assembled relocatable objects and compare the result with readelf. *)

open Elf_test_support
open Elf
module R = Elf_gnu.Readelf
module T = Elf_gnu.Toolchain

let ok what r = Check.ok ~pp_error:Decode.pp_error what r

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

(* Mismatches are collected so one run reports every disagreeing field. *)
let mismatches = ref []

let expect what expected actual =
  if expected <> actual then
    mismatches :=
      Printf.sprintf "%s: readelf says %s, Decode says %s" what expected actual :: !mismatches

let i64 v = Printf.sprintf "0x%Lx" v
let int v = string_of_int v

(* readelf prints ARM_ATTRIBUTES where Names uses the RISC-V name for the shared value. *)
let type_name (arch : Target.arch) v =
  match Format.asprintf "%a" Names.pp_sht v with
  | "RISCV_ATTRIBUTES" when arch = Arm -> "ARM_ATTRIBUTES"
  | n -> n

let flag_letters v = match Format.asprintf "%a" Names.pp_shf v with "-" -> "" | s -> s

let shndx_name v =
  if v = 0L then "UND"
  else if v = Int64.of_int Const.shn_abs then "ABS"
  else if v = Int64.of_int Const.shn_common then "COM"
  else Int64.to_string v

let vis_name other =
  match other land 3 with 0 -> "DEFAULT" | 1 -> "INTERNAL" | 2 -> "HIDDEN" | _ -> "PROTECTED"

(* readelf names a section symbol after its section. *)
let display_name (d : Decode.t) (s : Decode.symbol) =
  if s.sym_name = "" && Types.st_type s.sym.st_info = Const.stt_section then
    d.sections.(Int64.to_int s.shndx).name
  else s.sym_name

let check_sections arch (d : Decode.t) readelf_out =
  let rs = R.sections readelf_out in
  expect "section count" (int (List.length rs)) (int d.shnum);
  List.iter
    (fun (r : R.section) ->
      if r.nr < d.shnum then begin
        let s = d.sections.(r.nr) and what f = Printf.sprintf "section %d %s" r.nr f in
        expect (what "name") r.name s.name;
        expect (what "type") r.typ (type_name arch s.shdr.sh_type);
        expect (what "addr") (i64 r.addr) (i64 s.shdr.sh_addr);
        expect (what "offset") (i64 r.off) (i64 s.shdr.sh_offset);
        expect (what "size") (i64 r.size) (i64 s.shdr.sh_size);
        expect (what "entsize") (i64 r.es) (i64 s.shdr.sh_entsize);
        expect (what "flags") r.flags (flag_letters s.shdr.sh_flags);
        expect (what "link") (int r.lk) (Int64.to_string s.shdr.sh_link);
        expect (what "info") (int r.inf) (Int64.to_string s.shdr.sh_info);
        expect (what "align") (i64 r.al) (i64 s.shdr.sh_addralign)
      end)
    rs

let check_symbols (d : Decode.t) readelf_out =
  List.iter
    (fun (table, rsyms) ->
      match Decode.find_section d table with
      | None -> mismatches := ("no section " ^ table) :: !mismatches
      | Some sec ->
          let syms = ok "symbols" (Decode.symbols d sec) in
          expect (table ^ " entry count") (int (List.length rsyms)) (int (Array.length syms));
          List.iter
            (fun (r : R.symbol) ->
              if r.num < Array.length syms then begin
                let s = syms.(r.num) and what f = Printf.sprintf "%s[%d] %s" table r.num f in
                expect (what "name") r.name (display_name d s);
                expect (what "value") (i64 r.value) (i64 s.sym.st_value);
                expect (what "size") (i64 r.size) (i64 s.sym.st_size);
                expect (what "type") r.typ
                  (Format.asprintf "%a" Names.pp_stt (Types.st_type s.sym.st_info));
                expect (what "bind") r.bind
                  (Format.asprintf "%a" Names.pp_stb (Types.st_bind s.sym.st_info));
                expect (what "vis") r.vis (vis_name s.sym.st_other);
                expect (what "ndx") r.ndx (shndx_name s.shndx)
              end)
            rsyms)
    (R.symbols readelf_out)

let check_relocs (d : Decode.t) readelf_out =
  let cls = d.header.ident.elf_class in
  List.iter
    (fun (sect, rrels) ->
      match Decode.find_section d sect with
      | None -> mismatches := ("no section " ^ sect) :: !mismatches
      | Some sec ->
          let rels = ok "relocations" (Decode.relocations d sec) in
          let symtab = d.sections.(Int64.to_int sec.shdr.sh_link) in
          let syms = ok "symbols" (Decode.symbols d symtab) in
          expect (sect ^ " entry count") (int (List.length rrels)) (int (Array.length rels));
          List.iteri
            (fun i (r : R.reloc) ->
              if i < Array.length rels then begin
                let x = rels.(i) and what f = Printf.sprintf "%s[%d] %s" sect i f in
                expect (what "offset") (i64 r.offset) (i64 x.r_offset);
                let info =
                  match cls with
                  | Types.Elf32 -> Int64.logor (Int64.shift_left x.r_sym 8) x.r_type
                  | Types.Elf64 -> Int64.logor (Int64.shift_left x.r_sym 32) x.r_type
                in
                expect (what "info") (i64 r.info) (i64 info);
                let sym_name =
                  if x.r_sym = 0L then "" else display_name d syms.(Int64.to_int x.r_sym)
                in
                expect (what "symbol") r.sym_name sym_name;
                expect (what "addend")
                  (match r.addend with None -> "none" | Some a -> Int64.to_string a)
                  (match x.r_addend with None -> "none" | Some a -> Int64.to_string a)
              end)
            rrels)
    (R.relocs readelf_out)

let check_attributes (arch : Target.arch) (d : Decode.t) readelf_out =
  match
    (arch, Decode.find_section d (if arch = Arm then ".ARM.attributes" else ".riscv.attributes"))
  with
  | (Riscv32 | Riscv64 | Arm), Some sec ->
      let attrs = ok "attributes" (Decode.attributes d sec) in
      let ra = R.attributes readelf_out in
      let vendor = if arch = Arm then "aeabi" else "riscv" in
      let ours =
        List.concat_map
          (fun (s : Attributes.subsection) ->
            match s.contents with
            | `Parsed groups when s.vendor = vendor ->
                List.concat_map (fun (sc, l) -> if sc = Attributes.File then l else []) groups
            | _ -> [])
          attrs
      in
      expect "attribute count" (int (List.length ra)) (int (List.length ours));
      (* The string-valued CPU/arch tag (5 in both vendors) is printed quoted by readelf. *)
      let quoted =
        match List.assoc_opt 5 ours with
        | Some (Attributes.Ntbs s) -> "\"" ^ s ^ "\""
        | _ -> "<missing>"
      in
      let tag_name = if arch = Arm then "Tag_CPU_name" else "Tag_RISCV_arch" in
      expect tag_name (Option.value (List.assoc_opt tag_name ra) ~default:"<missing>") quoted
  | (Riscv32 | Riscv64 | Arm), None -> mismatches := "no attributes section" :: !mismatches
  | _ -> ()

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
      mismatches := [];
      check_sections arch d (readelf "-S");
      check_symbols d (readelf "-s");
      check_relocs d (readelf "-r");
      check_attributes arch d (readelf "-A");
      (* The object has relocations for .data, and the code uses a symbol this file does not define. *)
      match !mismatches with
      | [] -> ()
      | l -> Check.failf "\n  %s" (String.concat "\n  " (List.rev l)))

let () =
  Check.run "objects"
    (List.map
       (fun arch ->
         Check.case (Format.asprintf "%a" Target.pp_arch arch) (fun () -> test_arch arch))
       Target.all)
