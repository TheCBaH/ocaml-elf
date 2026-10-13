[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

type arch = X86_32 | X86_64 | Arm | Aarch64 | Riscv32 | Riscv64

type attributes = {
  section_name : string;
  section_type : int64;
  segment_type : int64 option;
  contents : Attributes.t;
}

type t = {
  arch : arch;
  elf_class : Types.elf_class;
  endianness : Types.endianness;
  machine : int;
  flags : int64;
  osabi : int;
  max_page_size : int64;
  attributes : attributes option;
}

let page_4k = 0x1000L

let make arch elf_class machine ?(flags = 0L) ?(max_page_size = page_4k) ?attributes () =
  {
    arch;
    elf_class;
    endianness = Types.Little;
    machine;
    flags;
    osabi = Const.elfosabi_none;
    max_page_size;
    attributes;
  }

let x86_32 = make X86_32 Types.Elf32 Const.em_386 ()
let x86_64 = make X86_64 Types.Elf64 Const.em_x86_64 ()

let aarch64 ?(page_size = 0x10000L) () =
  make Aarch64 Types.Elf64 Const.em_aarch64 ~max_page_size:page_size ()

let arm (abi : Arm.abi) =
  let attributes =
    Option.map
      (fun contents ->
        {
          section_name = ".ARM.attributes";
          section_type = Const.sht_arm_attributes;
          segment_type = None;
          contents;
        })
      abi.attributes
  in
  make Arm Types.Elf32 Const.em_arm ~flags:(Arm.flags abi) ?attributes ()

let riscv (abi : Riscv.abi) =
  let arch, elf_class =
    match abi.xlen with Riscv.Rv32 -> (Riscv32, Types.Elf32) | Riscv.Rv64 -> (Riscv64, Types.Elf64)
  in
  make arch elf_class Const.em_riscv ~flags:(Riscv.flags abi)
    ~attributes:
      {
        section_name = ".riscv.attributes";
        section_type = Const.sht_riscv_attributes;
        segment_type = Some Const.pt_riscv_attributes;
        contents = Riscv.attributes abi;
      }
    ()

let ident t =
  { Types.elf_class = t.elf_class; endianness = t.endianness; osabi = t.osabi; abiversion = 0 }

let names =
  [
    ("x86-32", X86_32);
    ("x86-64", X86_64);
    ("arm", Arm);
    ("aarch64", Aarch64);
    ("riscv32", Riscv32);
    ("riscv64", Riscv64);
  ]

let all = List.map snd names
let arch_of_string s = List.assoc_opt s names
let pp_arch ppf a = Format.pp_print_string ppf (fst (List.find (fun (_, v) -> v = a) names))
