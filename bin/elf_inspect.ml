[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

(* Stable, diff-friendly dump of a decoded ELF file: one record per line, key=value fields,
   hex for addresses. Not meant to look like readelf. *)

open Elf
open Types
open Err.Syntax

let usage =
  "usage: elf-inspect [--header] [--segments] [--sections] [--symbols] [--relocs] [--notes] \
   [--attributes] [--all] [--trace] FILE"

let hex ppf v = Format.fprintf ppf "0x%Lx" v

let hex_string s =
  String.concat "" (List.init (String.length s) (fun i -> Printf.sprintf "%02x" (Char.code s.[i])))

let header (d : Decode.t) =
  let h = d.header in
  Format.printf
    "header class=%a data=%a osabi=%d abiversion=%d type=%a machine=%a version=%Ld entry=%a \
     flags=%a phoff=%a shoff=%a ehsize=%d phentsize=%d phnum=%d shentsize=%d shnum=%d \
     shstrndx=%d@."
    pp_class h.ident.elf_class pp_endianness h.ident.endianness h.ident.osabi h.ident.abiversion
    Names.pp_et h.e_type Names.pp_em h.e_machine h.e_version hex h.e_entry hex h.e_flags hex
    h.e_phoff hex h.e_shoff h.e_ehsize h.e_phentsize d.phnum h.e_shentsize d.shnum d.shstrndx;
  Ok ()

let segments (d : Decode.t) =
  Array.iteri
    (fun i (p : phdr) ->
      Format.printf
        "segment index=%d type=%a flags=%a offset=%a vaddr=%a paddr=%a filesz=%a memsz=%a \
         align=%a@."
        i Names.pp_pt p.p_type Names.pp_pf p.p_flags hex p.p_offset hex p.p_vaddr hex p.p_paddr hex
        p.p_filesz hex p.p_memsz hex p.p_align)
    d.phdrs;
  Ok ()

let sections (d : Decode.t) =
  Array.iter
    (fun (s : Decode.section) ->
      let sh = s.shdr in
      Format.printf
        "section index=%d name=%S type=%a flags=%a addr=%a offset=%a size=%a link=%Ld info=%Ld \
         align=%Ld entsize=%Ld@."
        s.index s.name Names.pp_sht sh.sh_type Names.pp_shf sh.sh_flags hex sh.sh_addr hex
        sh.sh_offset hex sh.sh_size sh.sh_link sh.sh_info sh.sh_addralign sh.sh_entsize)
    d.sections;
  Ok ()

let of_type d types =
  List.filter
    (fun (s : Decode.section) -> List.mem s.shdr.sh_type types)
    (Array.to_list d.Decode.sections)

let symbols d =
  Err.List.iter
    (fun (s : Decode.section) ->
      let* syms = Decode.symbols d s in
      Array.iter
        (fun (y : Decode.symbol) ->
          Format.printf
            "symbol section=%S index=%d name=%S value=%a size=%a type=%a bind=%a other=%d \
             shndx=%a@."
            s.name y.sym_index y.sym_name hex y.sym.st_value hex y.sym.st_size Names.pp_stt
            (st_type y.sym.st_info) Names.pp_stb (st_bind y.sym.st_info) y.sym.st_other
            (fun ppf v ->
              match Names.shn (Int64.to_int v) with
              | Some n when Int64.compare v 0xffffL <= 0 && Int64.compare v 0L >= 0 ->
                  Format.pp_print_string ppf n
              | _ -> Format.fprintf ppf "%Ld" v)
            y.shndx)
        syms;
      Ok ())
    (of_type d [ Const.sht_symtab; Const.sht_dynsym ])

let relocs d =
  Err.List.iter
    (fun (s : Decode.section) ->
      let* rels = Decode.relocations d s in
      Array.iteri
        (fun i (r : rel) ->
          Format.printf "reloc section=%S index=%d offset=%a sym=%Ld type=%Ld%s@." s.name i hex
            r.r_offset r.r_sym r.r_type
            (match r.r_addend with None -> "" | Some a -> Printf.sprintf " addend=%Ld" a))
        rels;
      Ok ())
    (of_type d [ Const.sht_rel; Const.sht_rela ])

let notes (d : Decode.t) =
  let print where ns =
    List.iter
      (fun (n : Decode.note) ->
        Format.printf "note where=%s type=%Ld name=%S desc=%s@." where n.n_type n.n_name
          (hex_string n.n_desc))
      ns
  in
  let* () =
    Err.List.iter
      (fun (s : Decode.section) ->
        let+ ns = Decode.notes d (`Section s) in
        print (Printf.sprintf "section:%s" s.name) ns)
      (of_type d [ Const.sht_note ])
  in
  Err.List.iter
    (fun i ->
      let+ ns = Decode.notes d (`Segment i) in
      print (Printf.sprintf "segment:%d" i) ns)
    (List.filter (fun i -> d.phdrs.(i).p_type = Const.pt_note) (List.init d.phnum Fun.id))

let attributes d =
  let value ppf = function
    | Attributes.Uleb n -> Format.fprintf ppf "uleb=%Lu" n
    | Ntbs s -> Format.fprintf ppf "ntbs=%S" s
    | Uleb_ntbs (n, s) -> Format.fprintf ppf "uleb=%Lu ntbs=%S" n s
  in
  let scope ppf = function
    | Attributes.File -> Format.pp_print_string ppf "file"
    | (Section l | Symbol l) as sc ->
        Format.fprintf ppf "%s:%s"
          (match sc with Attributes.Section _ -> "section" | _ -> "symbol")
          (String.concat "," (List.map string_of_int l))
  in
  Err.List.iter
    (fun (s : Decode.section) ->
      let+ attrs = Decode.attributes d s in
      List.iter
        (fun (sub : Attributes.subsection) ->
          match sub.contents with
          | `Raw bytes ->
              Format.printf "attributes section=%S vendor=%S raw=%s@." s.name sub.vendor
                (hex_string bytes)
          | `Parsed groups ->
              List.iter
                (fun (sc, attrs) ->
                  List.iter
                    (fun (tag, v) ->
                      Format.printf "attribute section=%S vendor=%S scope=%a tag=%d %a@." s.name
                        sub.vendor scope sc tag value v)
                    attrs)
                groups)
        attrs)
    (of_type d [ Const.sht_riscv_attributes ])

let () =
  Err.Config.set Err.Config.deterministic;
  let selected = ref [] and file = ref None and trace = ref false in
  let flag name f = (name, Arg.Unit (fun () -> selected := f :: !selected), "") in
  let all = [ header; segments; sections; symbols; relocs; notes; attributes ] in
  let specs =
    [
      flag "--header" header;
      flag "--segments" segments;
      flag "--sections" sections;
      flag "--symbols" symbols;
      flag "--relocs" relocs;
      flag "--notes" notes;
      flag "--attributes" attributes;
      ("--trace", Arg.Set trace, " print where in the library a decode error was detected");
      ("--all", Arg.Unit (fun () -> selected := List.rev_append all !selected), "");
    ]
  in
  (try
     Arg.parse_argv Sys.argv specs
       (fun f -> if !file = None then file := Some f else raise (Arg.Bad "more than one FILE"))
       usage
   with
  | Arg.Bad msg ->
      prerr_string msg;
      exit 2
  | Arg.Help msg ->
      print_string msg;
      exit 0);
  match !file with
  | None ->
      prerr_endline usage;
      exit 2
  | Some path -> (
      match Elf_unix.read_file path with
      | Error e ->
          Format.eprintf "elf-inspect: %a@." (Err.Error.pp_kind Elf_unix.pp_error) e;
          exit 1
      | Ok data -> (
          let selected = if !selected = [] then [ header ] else List.rev !selected in
          let run =
            let* d = Decode.of_string data in
            Err.List.iter (fun f -> f d) selected
          in
          match run with
          | Ok () -> ()
          | Error e ->
              (* The trail names library source lines, which would make golden output
                 depend on every edit; it is opt-in. *)
              if !trace then Format.eprintf "elf-inspect: %a@." (Err.Error.pp Decode.pp_error) e
              else Format.eprintf "elf-inspect: %a@." (Err.Error.pp_kind Decode.pp_error) e;
              exit 2))
