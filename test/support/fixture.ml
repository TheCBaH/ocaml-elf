[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

open Elf.Types

type sect = {
  name : string;
  typ : int64;
  flags : int64;
  addr : int64;
  link : int;
  info : int64;
  align : int64;
  entsize : int64;
  data : string;
  size : int64 option;
}

let sect ?(flags = 0L) ?(addr = 0L) ?(link = 0) ?(info = 0L) ?(align = 1L) ?(entsize = 0L) ?size
    name typ data =
  { name; typ; flags; addr; link; info; align; entsize; data; size }

let align_to n a = (n + a - 1) / a * a

let build ?(e_type = 2) ?(machine = 243) ?(entry = 0L) ?(flags = 0L) ?(phdrs = fun _ -> []) cls
    endian sects =
  let ident = { elf_class = cls; endianness = endian; osabi = 0; abiversion = 0 } in
  let shstr = Buffer.create 64 in
  Buffer.add_char shstr '\000';
  let name_off name =
    if name = "" then 0
    else begin
      let o = Buffer.length shstr in
      Buffer.add_string shstr name;
      Buffer.add_char shstr '\000';
      o
    end
  in
  let sects = Array.of_list sects in
  let name_offs = Array.map (fun s -> name_off s.name) sects in
  let shstr_name = name_off ".shstrtab" in
  let nsect = Array.length sects + 2 in
  let shstrndx = nsect - 1 in
  let word = Codec.word_size cls in
  (* Section placement, in file order. *)
  let probe_phdrs = phdrs (Array.make nsect 0L) in
  let phnum = List.length probe_phdrs in
  let off = ref (Codec.ehdr_size cls + (phnum * Codec.phdr_size cls)) in
  let place s =
    let a = Int64.to_int s.align in
    off := align_to !off (max 1 a);
    let o = !off in
    off := o + String.length s.data;
    o
  in
  let sect_offs = Array.map place sects in
  let shstr_off = !off in
  off := shstr_off + Buffer.length shstr;
  let shoff = align_to !off word in
  let total = shoff + (nsect * Codec.shdr_size cls) in
  let b = Bytes.make total '\000' in
  let offsets =
    Array.concat [ [| 0L |]; Array.map Int64.of_int sect_offs; [| Int64.of_int shstr_off |] ]
  in
  List.iteri
    (fun i p -> Codec.write_phdr cls endian b (Codec.ehdr_size cls + (i * Codec.phdr_size cls)) p)
    (phdrs offsets);
  Array.iteri (fun i s -> Bytes.blit_string s.data 0 b sect_offs.(i) (String.length s.data)) sects;
  Bytes.blit_string (Buffer.contents shstr) 0 b shstr_off (Buffer.length shstr);
  let shdr_at i sh = Codec.write_shdr cls endian b (shoff + (i * Codec.shdr_size cls)) sh in
  let null =
    {
      sh_name = 0L;
      sh_type = 0L;
      sh_flags = 0L;
      sh_addr = 0L;
      sh_offset = 0L;
      sh_size = 0L;
      sh_link = 0L;
      sh_info = 0L;
      sh_addralign = 0L;
      sh_entsize = 0L;
    }
  in
  (* Extended numbering: the null section carries the counts. *)
  let big_shnum = nsect >= Elf.Const.shn_loreserve in
  let big_shstrndx = shstrndx >= Elf.Const.shn_loreserve in
  shdr_at 0
    {
      null with
      sh_size = (if big_shnum then Int64.of_int nsect else 0L);
      sh_link = (if big_shstrndx then Int64.of_int shstrndx else 0L);
    };
  Array.iteri
    (fun i s ->
      shdr_at (i + 1)
        {
          sh_name = Int64.of_int name_offs.(i);
          sh_type = s.typ;
          sh_flags = s.flags;
          sh_addr = s.addr;
          sh_offset = Int64.of_int sect_offs.(i);
          sh_size = Option.value s.size ~default:(Int64.of_int (String.length s.data));
          sh_link = Int64.of_int s.link;
          sh_info = s.info;
          sh_addralign = s.align;
          sh_entsize = s.entsize;
        })
    sects;
  shdr_at shstrndx
    {
      sh_name = Int64.of_int shstr_name;
      sh_type = Elf.Const.sht_strtab;
      sh_flags = 0L;
      sh_addr = 0L;
      sh_offset = Int64.of_int shstr_off;
      sh_size = Int64.of_int (Buffer.length shstr);
      sh_link = 0L;
      sh_info = 0L;
      sh_addralign = 1L;
      sh_entsize = 0L;
    };
  Codec.write_header b
    {
      ident;
      e_type;
      e_machine = machine;
      e_version = 1L;
      e_entry = entry;
      e_phoff = (if phnum = 0 then 0L else Int64.of_int (Codec.ehdr_size cls));
      e_shoff = Int64.of_int shoff;
      e_flags = flags;
      e_ehsize = Codec.ehdr_size cls;
      e_phentsize = Codec.phdr_size cls;
      e_phnum = phnum;
      e_shentsize = Codec.shdr_size cls;
      e_shnum = (if big_shnum then 0 else nsect);
      e_shstrndx = (if big_shstrndx then Elf.Const.shn_xindex else shstrndx);
    };
  Bytes.to_string b

let text_index = 1
let symtab_index = 2
let strtab_index = 3
let note_index = 4
let rela_index = 5
let shstrtab_index = 6

let minimal ?(cls = Elf32) ?(endian = Little) () =
  let open Elf.Const in
  let w v =
    (* a 32-bit field *)
    let b = Bytes.create 4 in
    Codec.set_u32 endian b 0 v;
    Bytes.to_string b
  in
  let strtab = "\000main\000data\000" in
  let sym name info shndx value size =
    let b = Bytes.make (Codec.sym_size cls) '\000' in
    Codec.write_sym cls endian b 0
      {
        st_name = name;
        st_info = info;
        st_other = 0;
        st_shndx = shndx;
        st_value = value;
        st_size = size;
      };
    Bytes.to_string b
  in
  let symtab =
    sym 0L 0 0 0L 0L
    ^ sym 6L (st_info ~bind:stb_local ~typ:stt_object) 1 0x10L 4L
    ^ sym 1L (st_info ~bind:stb_global ~typ:stt_func) 1 0L 8L
  in
  let rela =
    let b = Bytes.make (Codec.rela_size cls) '\000' in
    Codec.write_rel cls endian b 0 { r_offset = 4L; r_sym = 2L; r_type = 5L; r_addend = Some (-4L) };
    Bytes.to_string b
  in
  (* One note: name "GNU", type 1, a 4-byte descriptor. *)
  let note = w 4L ^ w 4L ^ w 1L ^ "GNU\000" ^ "\001\002\003\004" in
  build cls endian ~entry:0x1000L
    ~phdrs:(fun offs ->
      let phdr p_type p_flags o size =
        {
          p_type;
          p_flags;
          p_offset = o;
          p_vaddr = Int64.add 0x1000L o;
          p_paddr = Int64.add 0x1000L o;
          p_filesz = size;
          p_memsz = size;
          p_align = 4L;
        }
      in
      [
        phdr pt_load (Int64.logor pf_r pf_x) offs.(text_index) 16L;
        phdr pt_note pf_r offs.(note_index) (Int64.of_int (String.length note));
      ])
    [
      sect ".text" sht_progbits (String.make 16 '\x90')
        ~flags:(Int64.logor shf_alloc shf_execinstr)
        ~addr:0x1000L ~align:4L;
      sect ".symtab" sht_symtab symtab ~link:strtab_index ~info:1L
        ~align:(Int64.of_int (Codec.word_size cls))
        ~entsize:(Int64.of_int (Codec.sym_size cls));
      sect ".strtab" sht_strtab strtab;
      sect ".note.test" sht_note note ~align:4L;
      sect ".rela.text" sht_rela rela ~link:symtab_index ~info:1L
        ~align:(Int64.of_int (Codec.word_size cls))
        ~entsize:(Int64.of_int (Codec.rela_size cls));
    ]

let many_sections ?(cls = Elf32) ?(endian = Little) n =
  build cls endian (List.init n (fun i -> sect (Printf.sprintf "s%d" i) Elf.Const.sht_progbits ""))

(* {1 Mutators} *)

let ident_of s =
  (* A truncated file has no class or byte-order byte: fall back to ELF32 little-endian. *)
  let byte i = if i < String.length s then Char.code s.[i] else 0 in
  {
    elf_class = (if byte 4 = 2 then Elf64 else Elf32);
    endianness = (if byte 5 = 2 then Big else Little);
    osabi = 0;
    abiversion = 0;
  }

let truncate n s = String.sub s 0 n

let patch s f =
  let b = Bytes.of_string s in
  f (ident_of s) b;
  Bytes.to_string b

let set_u8 off v s = patch s (fun _ b -> Codec.set_u8 b off v)
let set_u16 off v s = patch s (fun id b -> Codec.set_u16 id.endianness b off v)
let set_u32 off v s = patch s (fun id b -> Codec.set_u32 id.endianness b off v)
let set_word off v s = patch s (fun id b -> Codec.set_word id.elf_class id.endianness b off v)
let header s = Codec.read_header (ident_of s) s
let with_header f s = patch s (fun _ b -> Codec.write_header b (f (header s)))

let shdr_offset s i =
  let h = header s in
  Int64.to_int h.e_shoff + (i * Codec.shdr_size h.ident.elf_class)

let with_shdr i f s =
  patch s (fun id b ->
      let off = shdr_offset s i in
      Codec.write_shdr id.elf_class id.endianness b off
        (f (Codec.read_shdr id.elf_class id.endianness s off)))

let with_phdr i f s =
  patch s (fun id b ->
      let h = header s in
      let off = Int64.to_int h.e_phoff + (i * Codec.phdr_size id.elf_class) in
      Codec.write_phdr id.elf_class id.endianness b off
        (f (Codec.read_phdr id.elf_class id.endianness s off)))
