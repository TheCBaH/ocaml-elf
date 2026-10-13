(* Field layouts of every fixed-size ELF record, for both classes and both byte
   orders. The readers and writers here do no validation: Decode checks bounds
   before calling a reader, and Encode checks field widths before calling a
   writer. Keeping both directions in one file keeps each record's offsets in
   one place.

   ELF32 and ELF64 differ in more than word size: a program header's p_flags
   follows p_type in ELF64 but p_memsz in ELF32, and a symbol's st_value/st_size
   come before st_info in ELF32 but after st_shndx in ELF64. *)

open Types

let ehdr_size = function Elf32 -> 52 | Elf64 -> 64
let phdr_size = function Elf32 -> 32 | Elf64 -> 56
let shdr_size = function Elf32 -> 40 | Elf64 -> 64
let sym_size = function Elf32 -> 16 | Elf64 -> 24
let rel_size = function Elf32 -> 8 | Elf64 -> 16
let rela_size = function Elf32 -> 12 | Elf64 -> 24
let word_size = function Elf32 -> 4 | Elf64 -> 8
let word_bits = function Elf32 -> 32 | Elf64 -> 64
let ei_nident = 16
let magic = "\x7fELF"

(* {1 Scalars} *)

let get_u8 s off = String.get_uint8 s off

let get_u16 e s off =
  match e with Little -> String.get_uint16_le s off | Big -> String.get_uint16_be s off

let get_u32 e s off =
  let v = match e with Little -> String.get_int32_le s off | Big -> String.get_int32_be s off in
  Int64.logand (Int64.of_int32 v) 0xffff_ffffL

let get_u64 e s off =
  match e with Little -> String.get_int64_le s off | Big -> String.get_int64_be s off

let get_word c e s off = match c with Elf32 -> get_u32 e s off | Elf64 -> get_u64 e s off
let set_u8 b off v = Bytes.set_uint8 b off v

let set_u16 e b off v =
  match e with Little -> Bytes.set_uint16_le b off v | Big -> Bytes.set_uint16_be b off v

let set_u32 e b off v =
  let v = Int64.to_int32 v in
  match e with Little -> Bytes.set_int32_le b off v | Big -> Bytes.set_int32_be b off v

let set_u64 e b off v =
  match e with Little -> Bytes.set_int64_le b off v | Big -> Bytes.set_int64_be b off v

let set_word c e b off v = match c with Elf32 -> set_u32 e b off v | Elf64 -> set_u64 e b off v

(* {1 ELF header}

   e_entry starts at 24 in both classes; the three words and the 32-bit flags
   follow, then six 16-bit fields. *)

let class_byte = function Elf32 -> 1 | Elf64 -> 2
let data_byte = function Little -> 1 | Big -> 2

let read_header ident s =
  let c = ident.elf_class and e = ident.endianness in
  let w = word_size c in
  let h16 i = get_u16 e s (28 + (3 * w) + (2 * i)) in
  {
    ident;
    e_type = get_u16 e s 16;
    e_machine = get_u16 e s 18;
    e_version = get_u32 e s 20;
    e_entry = get_word c e s 24;
    e_phoff = get_word c e s (24 + w);
    e_shoff = get_word c e s (24 + (2 * w));
    e_flags = get_u32 e s (24 + (3 * w));
    e_ehsize = h16 0;
    e_phentsize = h16 1;
    e_phnum = h16 2;
    e_shentsize = h16 3;
    e_shnum = h16 4;
    e_shstrndx = h16 5;
  }

let write_header b h =
  let c = h.ident.elf_class and e = h.ident.endianness in
  let w = word_size c in
  Bytes.blit_string magic 0 b 0 4;
  set_u8 b 4 (class_byte c);
  set_u8 b 5 (data_byte e);
  set_u8 b 6 Const.ev_current;
  set_u8 b 7 h.ident.osabi;
  set_u8 b 8 h.ident.abiversion;
  Bytes.fill b 9 7 '\000';
  set_u16 e b 16 h.e_type;
  set_u16 e b 18 h.e_machine;
  set_u32 e b 20 h.e_version;
  set_word c e b 24 h.e_entry;
  set_word c e b (24 + w) h.e_phoff;
  set_word c e b (24 + (2 * w)) h.e_shoff;
  set_u32 e b (24 + (3 * w)) h.e_flags;
  List.iteri
    (fun i v -> set_u16 e b (28 + (3 * w) + (2 * i)) v)
    [ h.e_ehsize; h.e_phentsize; h.e_phnum; h.e_shentsize; h.e_shnum; h.e_shstrndx ]

(* {1 Program header} *)

let read_phdr c e s off =
  let u32 i = get_u32 e s (off + i) and word i = get_word c e s (off + i) in
  match c with
  | Elf32 ->
      {
        p_type = u32 0;
        p_offset = word 4;
        p_vaddr = word 8;
        p_paddr = word 12;
        p_filesz = word 16;
        p_memsz = word 20;
        p_flags = u32 24;
        p_align = word 28;
      }
  | Elf64 ->
      {
        p_type = u32 0;
        p_flags = u32 4;
        p_offset = word 8;
        p_vaddr = word 16;
        p_paddr = word 24;
        p_filesz = word 32;
        p_memsz = word 40;
        p_align = word 48;
      }

let write_phdr c e b off p =
  let u32 i v = set_u32 e b (off + i) v and word i v = set_word c e b (off + i) v in
  match c with
  | Elf32 ->
      u32 0 p.p_type;
      word 4 p.p_offset;
      word 8 p.p_vaddr;
      word 12 p.p_paddr;
      word 16 p.p_filesz;
      word 20 p.p_memsz;
      u32 24 p.p_flags;
      word 28 p.p_align
  | Elf64 ->
      u32 0 p.p_type;
      u32 4 p.p_flags;
      word 8 p.p_offset;
      word 16 p.p_vaddr;
      word 24 p.p_paddr;
      word 32 p.p_filesz;
      word 40 p.p_memsz;
      word 48 p.p_align

(* {1 Section header}

   Same field order in both classes: two 32-bit fields, four words, two 32-bit
   fields, two words. *)

let read_shdr c e s off =
  let w = word_size c in
  let u32 i = get_u32 e s (off + i) and word i = get_word c e s (off + i) in
  {
    sh_name = u32 0;
    sh_type = u32 4;
    sh_flags = word 8;
    sh_addr = word (8 + w);
    sh_offset = word (8 + (2 * w));
    sh_size = word (8 + (3 * w));
    sh_link = u32 (8 + (4 * w));
    sh_info = u32 (12 + (4 * w));
    sh_addralign = word (16 + (4 * w));
    sh_entsize = word (16 + (5 * w));
  }

let write_shdr c e b off sh =
  let w = word_size c in
  let u32 i v = set_u32 e b (off + i) v and word i v = set_word c e b (off + i) v in
  u32 0 sh.sh_name;
  u32 4 sh.sh_type;
  word 8 sh.sh_flags;
  word (8 + w) sh.sh_addr;
  word (8 + (2 * w)) sh.sh_offset;
  word (8 + (3 * w)) sh.sh_size;
  u32 (8 + (4 * w)) sh.sh_link;
  u32 (12 + (4 * w)) sh.sh_info;
  word (16 + (4 * w)) sh.sh_addralign;
  word (16 + (5 * w)) sh.sh_entsize

(* {1 Symbol} *)

let read_sym c e s off =
  match c with
  | Elf32 ->
      {
        st_name = get_u32 e s off;
        st_value = get_u32 e s (off + 4);
        st_size = get_u32 e s (off + 8);
        st_info = get_u8 s (off + 12);
        st_other = get_u8 s (off + 13);
        st_shndx = get_u16 e s (off + 14);
      }
  | Elf64 ->
      {
        st_name = get_u32 e s off;
        st_info = get_u8 s (off + 4);
        st_other = get_u8 s (off + 5);
        st_shndx = get_u16 e s (off + 6);
        st_value = get_u64 e s (off + 8);
        st_size = get_u64 e s (off + 16);
      }

let write_sym c e b off sym =
  match c with
  | Elf32 ->
      set_u32 e b off sym.st_name;
      set_u32 e b (off + 4) sym.st_value;
      set_u32 e b (off + 8) sym.st_size;
      set_u8 b (off + 12) sym.st_info;
      set_u8 b (off + 13) sym.st_other;
      set_u16 e b (off + 14) sym.st_shndx
  | Elf64 ->
      set_u32 e b off sym.st_name;
      set_u8 b (off + 4) sym.st_info;
      set_u8 b (off + 5) sym.st_other;
      set_u16 e b (off + 6) sym.st_shndx;
      set_u64 e b (off + 8) sym.st_value;
      set_u64 e b (off + 16) sym.st_size

(* {1 Relocation}

   ELF32 packs r_info as sym << 8 | type (8 bits); ELF64 as sym << 32 | type
   (32 bits). The ELF32 addend is a signed 32-bit field. *)

let read_rel ~rela c e s off =
  match c with
  | Elf32 ->
      let info = get_u32 e s (off + 4) in
      {
        r_offset = get_u32 e s off;
        r_sym = Int64.shift_right_logical info 8;
        r_type = Int64.logand info 0xffL;
        r_addend =
          (if rela then Some (Int64.of_int32 (Int64.to_int32 (get_u32 e s (off + 8)))) else None);
      }
  | Elf64 ->
      let info = get_u64 e s (off + 8) in
      {
        r_offset = get_u64 e s off;
        r_sym = Int64.shift_right_logical info 32;
        r_type = Int64.logand info 0xffff_ffffL;
        r_addend = (if rela then Some (get_u64 e s (off + 16)) else None);
      }

let write_rel c e b off r =
  match c with
  | Elf32 ->
      set_u32 e b off r.r_offset;
      set_u32 e b (off + 4) (Int64.logor (Int64.shift_left r.r_sym 8) r.r_type);
      Option.iter (fun a -> set_u32 e b (off + 8) (Int64.logand a 0xffff_ffffL)) r.r_addend
  | Elf64 ->
      set_u64 e b off r.r_offset;
      set_u64 e b (off + 8) (Int64.logor (Int64.shift_left r.r_sym 32) r.r_type);
      Option.iter (fun a -> set_u64 e b (off + 16) a) r.r_addend
