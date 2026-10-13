(* Comparisons of a decoded file with the output of readelf -W. Mismatches are collected so one run
   reports every disagreeing field. *)

open Elf

let ok what r = Check.ok ~pp_error:Decode.pp_error what r

module R = Readelf

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

(* The names readelf prints for the machines the fixtures use. *)
let machine_name = function
  | 3 -> "Intel 80386"
  | 40 -> "ARM"
  | 62 -> "Advanced Micro Devices X86-64"
  | 183 -> "AArch64"
  | 243 -> "RISC-V"
  | m -> Printf.sprintf "<unknown: %x>" m

let type_description (d : Decode.t) =
  match d.header.e_type with
  | 1 -> "REL (Relocatable file)"
  | 2 -> "EXEC (Executable file)"
  | 3 -> "DYN (Shared object file)"
  | t -> Printf.sprintf "<unknown: %x>" t

let first_token s = match String.split_on_char ' ' (String.trim s) with t :: _ -> t | [] -> ""

let check_header (d : Decode.t) readelf_out =
  let h = R.header readelf_out in
  let field k = Option.value (List.assoc_opt k h) ~default:"<missing>" in
  expect "Type" (field "Type") (type_description d);
  expect "Machine" (field "Machine") (machine_name d.header.e_machine);
  expect "Entry point address" (field "Entry point address") (i64 d.header.e_entry);
  let flags = first_token (String.concat " " (String.split_on_char ',' (field "Flags"))) in
  expect "Flags" flags (i64 d.header.e_flags);
  expect "Number of program headers" (first_token (field "Number of program headers")) (int d.phnum);
  expect "Number of section headers" (first_token (field "Number of section headers")) (int d.shnum);
  if d.shnum > 0 then
    expect "Section header string table index"
      (first_token (field "Section header string table index"))
      (int d.shstrndx)

(* readelf shortens long type names and spells a few differently. *)
let same_segment_type theirs ours =
  theirs = ours
  || (String.length theirs < String.length ours && String.sub ours 0 (String.length theirs) = theirs)
  || (theirs = "EXIDX" && ours = "ARM_EXIDX")

let segment_flags theirs =
  String.concat "" (String.split_on_char ' ' (String.map (function 'E' -> 'X' | c -> c) theirs))

let check_segments (d : Decode.t) readelf_out =
  let rs = R.segments readelf_out in
  expect "program header count" (int (List.length rs)) (int d.phnum);
  List.iteri
    (fun i (r : R.segment) ->
      if i < d.phnum then begin
        let p = d.phdrs.(i) and what f = Printf.sprintf "program header %d %s" i f in
        let ours = Format.asprintf "%a" Names.pp_pt p.p_type in
        if not (same_segment_type r.ptype ours) then
          mismatches :=
            Printf.sprintf "%s: readelf says %s, Decode says %s" (what "type") r.ptype ours
            :: !mismatches;
        expect (what "offset") (i64 r.p_offset) (i64 p.p_offset);
        expect (what "vaddr") (i64 r.vaddr) (i64 p.p_vaddr);
        expect (what "paddr") (i64 r.paddr) (i64 p.p_paddr);
        expect (what "filesz") (i64 r.filesz) (i64 p.p_filesz);
        expect (what "memsz") (i64 r.memsz) (i64 p.p_memsz);
        expect (what "flags") (segment_flags r.pflags)
          (match Format.asprintf "%a" Names.pp_pf p.p_flags with "-" -> "" | f -> f);
        expect (what "align") (i64 r.palign) (i64 p.p_align)
      end)
    rs

let check_notes (d : Decode.t) readelf_out =
  let rs = R.notes readelf_out in
  Array.iter
    (fun (s : Decode.section) ->
      if s.shdr.sh_type = Const.sht_note then begin
        let notes = ok "notes" (Decode.notes d (`Section s)) in
        let ours =
          List.map
            (fun (n : Decode.note) -> (n.n_name, Int64.of_int (String.length n.n_desc)))
            notes
        in
        match List.assoc_opt s.name rs with
        | None -> mismatches := Printf.sprintf "readelf shows no notes in %s" s.name :: !mismatches
        | Some theirs ->
            let show l =
              String.concat "," (List.map (fun (o, n) -> Printf.sprintf "%s/%Ld" o n) l)
            in
            expect (s.name ^ " notes") (show theirs) (show ours)
      end)
    d.sections
