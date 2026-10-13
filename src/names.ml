[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

let lookup table v = List.assoc_opt v table

let et =
  lookup
    Const.
      [ (et_none, "NONE"); (et_rel, "REL"); (et_exec, "EXEC"); (et_dyn, "DYN"); (et_core, "CORE") ]

let em =
  lookup
    Const.
      [
        (em_386, "386");
        (em_arm, "ARM");
        (em_x86_64, "X86_64");
        (em_aarch64, "AARCH64");
        (em_riscv, "RISCV");
      ]

let pt =
  lookup
    Const.
      [
        (pt_null, "NULL");
        (pt_load, "LOAD");
        (pt_dynamic, "DYNAMIC");
        (pt_interp, "INTERP");
        (pt_note, "NOTE");
        (pt_shlib, "SHLIB");
        (pt_phdr, "PHDR");
        (pt_tls, "TLS");
        (pt_gnu_eh_frame, "GNU_EH_FRAME");
        (pt_gnu_stack, "GNU_STACK");
        (pt_gnu_relro, "GNU_RELRO");
        (pt_gnu_property, "GNU_PROPERTY");
        (pt_arm_exidx, "ARM_EXIDX");
        (pt_riscv_attributes, "RISCV_ATTRIBUTES");
      ]

(* SHT_ARM_ATTRIBUTES and SHT_RISCV_ATTRIBUTES are the same value, 0x70000003;
   the name here is the RISC-V one, which is the target this library is built
   around. *)
let sht =
  lookup
    Const.
      [
        (sht_null, "NULL");
        (sht_progbits, "PROGBITS");
        (sht_symtab, "SYMTAB");
        (sht_strtab, "STRTAB");
        (sht_rela, "RELA");
        (sht_hash, "HASH");
        (sht_dynamic, "DYNAMIC");
        (sht_note, "NOTE");
        (sht_nobits, "NOBITS");
        (sht_rel, "REL");
        (sht_dynsym, "DYNSYM");
        (sht_init_array, "INIT_ARRAY");
        (sht_fini_array, "FINI_ARRAY");
        (sht_preinit_array, "PREINIT_ARRAY");
        (sht_group, "GROUP");
        (sht_symtab_shndx, "SYMTAB_SHNDX");
        (sht_gnu_hash, "GNU_HASH");
        (sht_gnu_verdef, "VERDEF");
        (sht_gnu_verneed, "VERNEED");
        (sht_gnu_versym, "VERSYM");
        (sht_arm_exidx, "ARM_EXIDX");
        (sht_riscv_attributes, "RISCV_ATTRIBUTES");
      ]

let stb = lookup Const.[ (stb_local, "LOCAL"); (stb_global, "GLOBAL"); (stb_weak, "WEAK") ]

let stt =
  lookup
    Const.
      [
        (stt_notype, "NOTYPE");
        (stt_object, "OBJECT");
        (stt_func, "FUNC");
        (stt_section, "SECTION");
        (stt_file, "FILE");
      ]

let shn =
  lookup
    Const.[ (shn_undef, "UND"); (shn_abs, "ABS"); (shn_common, "COMMON"); (shn_xindex, "XINDEX") ]

let pp_named name pp_hex ppf v =
  match name v with Some s -> Format.pp_print_string ppf s | None -> pp_hex ppf v

let hex_int ppf v = Format.fprintf ppf "0x%x" v
let hex_int64 ppf v = Format.fprintf ppf "0x%Lx" v
let pp_et = pp_named et hex_int
let pp_em = pp_named em hex_int
let pp_pt = pp_named pt hex_int64
let pp_sht = pp_named sht hex_int64
let pp_stb = pp_named stb hex_int
let pp_stt = pp_named stt hex_int
let pp_shn = pp_named shn hex_int

let pp_flags letters ~empty ppf v =
  let known = List.fold_left (fun acc (bit, _) -> Int64.logor acc bit) 0L letters in
  let shown = List.filter (fun (bit, _) -> Int64.logand v bit <> 0L) letters in
  List.iter (fun (_, c) -> Format.pp_print_char ppf c) shown;
  let residual = Int64.logand v (Int64.lognot known) in
  if residual <> 0L then Format.fprintf ppf "+0x%Lx" residual
  else if shown = [] then Format.pp_print_string ppf empty

let pp_pf = pp_flags Const.[ (pf_r, 'R'); (pf_w, 'W'); (pf_x, 'X') ] ~empty:"-"

let pp_shf =
  pp_flags
    Const.
      [
        (shf_write, 'W');
        (shf_alloc, 'A');
        (shf_execinstr, 'X');
        (shf_merge, 'M');
        (shf_strings, 'S');
        (shf_info_link, 'I');
        (shf_link_order, 'L');
        (shf_os_nonconforming, 'O');
        (shf_group, 'G');
        (shf_tls, 'T');
        (shf_compressed, 'C');
      ]
    ~empty:"-"
