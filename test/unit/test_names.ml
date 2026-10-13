[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

open Elf_test_support
open Elf

let str ppf s = Format.pp_print_string ppf s
let show pp v = Format.asprintf "%a" pp v
let eq what expected actual = Check.equal ~pp:str what expected actual

(* Every constant in Const that has a name, with the name it must print. *)
let named lookup what table =
  Check.case what (fun () ->
      List.iter
        (fun (v, name) ->
          match lookup v with
          | Some n -> eq name name n
          | None -> Check.failf "%s: %s has no name" what name)
        table)

let () =
  Check.run "names"
    [
      named Names.et "et"
        Const.
          [
            (et_none, "NONE"); (et_rel, "REL"); (et_exec, "EXEC"); (et_dyn, "DYN"); (et_core, "CORE");
          ];
      named Names.em "em"
        Const.
          [
            (em_386, "386");
            (em_arm, "ARM");
            (em_x86_64, "X86_64");
            (em_aarch64, "AARCH64");
            (em_riscv, "RISCV");
          ];
      named Names.pt "pt"
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
          ];
      named Names.sht "sht"
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
            (sht_arm_exidx, "ARM_EXIDX");
            (sht_arm_attributes, "RISCV_ATTRIBUTES");
          ];
      named Names.stb "stb"
        Const.[ (stb_local, "LOCAL"); (stb_global, "GLOBAL"); (stb_weak, "WEAK") ];
      named Names.stt "stt"
        Const.
          [
            (stt_notype, "NOTYPE");
            (stt_object, "OBJECT");
            (stt_func, "FUNC");
            (stt_section, "SECTION");
            (stt_file, "FILE");
          ];
      named Names.shn "shn"
        Const.
          [ (shn_undef, "UND"); (shn_abs, "ABS"); (shn_common, "COMMON"); (shn_xindex, "XINDEX") ];
      Check.case "unknown values print as hex" (fun () ->
          eq "pt" "0x6fff0000" (show Names.pp_pt 0x6fff_0000L);
          eq "sht" "0x12345" (show Names.pp_sht 0x12345L);
          eq "em" "0xabcd" (show Names.pp_em 0xabcd);
          eq "known" "LOAD" (show Names.pp_pt Const.pt_load);
          eq "shn" "0xff00" (show Names.pp_shn Const.shn_loreserve));
      Check.case "flags" (fun () ->
          eq "shf residual" "AX+0x80000000" (show Names.pp_shf 0x8000_0006L);
          eq "shf WAX" "WAX" (show Names.pp_shf 0x7L);
          eq "shf none" "-" (show Names.pp_shf 0L);
          eq "pf rx" "RX" (show Names.pp_pf 5L);
          eq "pf rw" "RW" (show Names.pp_pf 6L);
          eq "pf none" "-" (show Names.pp_pf 0L);
          eq "pf residual" "R+0x100000" (show Names.pp_pf 0x10_0004L));
    ]
