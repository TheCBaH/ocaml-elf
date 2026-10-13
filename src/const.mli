(** Named numeric constants from the ELF, GNU, RISC-V and ARM specifications.

    They name values; they do not restrict them. Every field they belong to is an open integer, and
    decoding keeps unknown values, so a constant is never a closed variant. Values of 32 bits or
    more are [int64] bit patterns (see {!U64}); smaller ones are [int]. Printers are in {!Names}. *)

(* e_ident *)
val elfosabi_none : int
val ev_current : int

(* e_type *)
val et_none : int
val et_rel : int
val et_exec : int
val et_dyn : int
val et_core : int

(* e_machine *)
val em_386 : int
val em_arm : int
val em_x86_64 : int
val em_aarch64 : int
val em_riscv : int

(* p_type *)
val pt_null : int64
val pt_load : int64
val pt_dynamic : int64
val pt_interp : int64
val pt_note : int64
val pt_shlib : int64
val pt_phdr : int64
val pt_tls : int64
val pt_gnu_eh_frame : int64
val pt_gnu_stack : int64
val pt_gnu_relro : int64
val pt_gnu_property : int64
val pt_arm_exidx : int64
val pt_riscv_attributes : int64

(* p_flags *)
val pf_x : int64
val pf_w : int64
val pf_r : int64

(* sh_type *)
val sht_null : int64
val sht_progbits : int64
val sht_symtab : int64
val sht_strtab : int64
val sht_rela : int64
val sht_hash : int64
val sht_dynamic : int64
val sht_note : int64
val sht_nobits : int64
val sht_rel : int64
val sht_dynsym : int64
val sht_init_array : int64
val sht_fini_array : int64
val sht_preinit_array : int64
val sht_group : int64
val sht_symtab_shndx : int64
val sht_gnu_verdef : int64
val sht_gnu_verneed : int64
val sht_gnu_versym : int64
val sht_gnu_hash : int64
val sht_arm_exidx : int64
val sht_arm_attributes : int64
val sht_riscv_attributes : int64

(* sh_flags *)
val shf_write : int64
val shf_alloc : int64
val shf_execinstr : int64
val shf_merge : int64
val shf_strings : int64
val shf_info_link : int64
val shf_link_order : int64
val shf_os_nonconforming : int64
val shf_group : int64
val shf_tls : int64
val shf_compressed : int64

(* Special section indices *)
val shn_undef : int
val shn_loreserve : int
val shn_abs : int
val shn_common : int
val shn_xindex : int

(* Extended program header numbering *)
val pn_xnum : int

(* Symbol binding and type *)
val stb_local : int
val stb_global : int
val stb_weak : int
val stt_notype : int
val stt_object : int
val stt_func : int
val stt_section : int
val stt_file : int
val stv_default : int

(* RISC-V e_flags *)
val ef_riscv_rvc : int64
val ef_riscv_float_abi_soft : int64
val ef_riscv_float_abi_single : int64
val ef_riscv_float_abi_double : int64
val ef_riscv_float_abi_quad : int64
val ef_riscv_rve : int64
val ef_riscv_tso : int64

(* ARM e_flags *)
val ef_arm_eabi_ver5 : int64
val ef_arm_abi_float_soft : int64
val ef_arm_abi_float_hard : int64
