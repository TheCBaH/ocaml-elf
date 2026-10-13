(* Named numeric constants. They name values; they do not restrict them: every
   field these belong to is an open integer, and decoding keeps unknown values. *)

(* e_ident *)
let elfosabi_none = 0
let ev_current = 1

(* e_type *)
let et_none = 0
let et_rel = 1
let et_exec = 2
let et_dyn = 3
let et_core = 4

(* e_machine *)
let em_386 = 3
let em_arm = 40
let em_x86_64 = 62
let em_aarch64 = 183
let em_riscv = 243

(* p_type *)
let pt_null = 0L
let pt_load = 1L
let pt_dynamic = 2L
let pt_interp = 3L
let pt_note = 4L
let pt_shlib = 5L
let pt_phdr = 6L
let pt_tls = 7L
let pt_gnu_eh_frame = 0x6474e550L
let pt_gnu_stack = 0x6474e551L
let pt_gnu_relro = 0x6474e552L
let pt_gnu_property = 0x6474e553L
let pt_arm_exidx = 0x70000001L
let pt_riscv_attributes = 0x70000003L

(* p_flags *)
let pf_x = 1L
let pf_w = 2L
let pf_r = 4L

(* sh_type *)
let sht_null = 0L
let sht_progbits = 1L
let sht_symtab = 2L
let sht_strtab = 3L
let sht_rela = 4L
let sht_hash = 5L
let sht_dynamic = 6L
let sht_note = 7L
let sht_nobits = 8L
let sht_rel = 9L
let sht_dynsym = 11L
let sht_init_array = 14L
let sht_fini_array = 15L
let sht_preinit_array = 16L
let sht_group = 17L
let sht_symtab_shndx = 18L
let sht_gnu_verdef = 0x6ffffffdL
let sht_gnu_verneed = 0x6ffffffeL
let sht_gnu_versym = 0x6fffffffL
let sht_gnu_hash = 0x6ffffff6L
let sht_arm_exidx = 0x70000001L
let sht_arm_attributes = 0x70000003L
let sht_riscv_attributes = 0x70000003L

(* sh_flags *)
let shf_write = 0x1L
let shf_alloc = 0x2L
let shf_execinstr = 0x4L
let shf_merge = 0x10L
let shf_strings = 0x20L
let shf_info_link = 0x40L
let shf_link_order = 0x80L
let shf_os_nonconforming = 0x100L
let shf_group = 0x200L
let shf_tls = 0x400L
let shf_compressed = 0x800L

(* Special section indices *)
let shn_undef = 0
let shn_loreserve = 0xff00
let shn_abs = 0xfff1
let shn_common = 0xfff2
let shn_xindex = 0xffff

(* Extended program header numbering *)
let pn_xnum = 0xffff

(* Symbol binding and type *)
let stb_local = 0
let stb_global = 1
let stb_weak = 2
let stt_notype = 0
let stt_object = 1
let stt_func = 2
let stt_section = 3
let stt_file = 4
let stv_default = 0

(* RISC-V e_flags *)
let ef_riscv_rvc = 0x1L
let ef_riscv_float_abi_soft = 0x0L
let ef_riscv_float_abi_single = 0x2L
let ef_riscv_float_abi_double = 0x4L
let ef_riscv_float_abi_quad = 0x6L
let ef_riscv_rve = 0x8L
let ef_riscv_tso = 0x10L

(* ARM e_flags *)
let ef_arm_eabi_ver5 = 0x05000000L
let ef_arm_abi_float_soft = 0x200L
let ef_arm_abi_float_hard = 0x400L
