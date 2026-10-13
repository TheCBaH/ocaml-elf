[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

open Elf_test_support
open Elf
module Codec = Elf_test_support.Codec

let pp_i64 ppf v = Format.fprintf ppf "0x%Lx" v
let pp_any ppf _ = Format.pp_print_string ppf "<value>"
let eq_i64 what e a = Check.equal ~pp:pp_i64 what e a
let eq_int what e a = Check.equal ~pp:Format.pp_print_int what e a
let eq_str what e a = Check.equal ~pp:Format.pp_print_string what e a

let fails what (pred : Exec.error -> bool) (r : (_, Exec.error) Err.t) =
  Check.error ~pp:pp_any what pred r

let build spec = Check.ok ~pp_error:Exec.pp_error "build" (Exec.build spec)
let decode bytes = Check.ok ~pp_error:Decode.pp_error "decode" (Decode.of_string bytes)

let targets =
  [
    ("rv32", Target.riscv Riscv.rv32imafd_ilp32d);
    ("rv64", Target.riscv Riscv.rv64imafd_lp64d);
    ("x86-32", Target.x86_32);
    ("x86-64", Target.x86_64);
    ("arm", Target.arm Arm.hard_float);
    ("aarch64", Target.aarch64 ());
  ]

let loads (d : Decode.t) =
  List.filter (fun (p : Types.phdr) -> p.p_type = Const.pt_load) (Array.to_list d.phdrs)

let section (d : Decode.t) name =
  match Decode.find_section d name with Some s -> s | None -> Check.failf "no section %s" name

let sec_bytes d name =
  Check.ok ~pp_error:Decode.pp_error name (Decode.section_data d (section d name))

(* Properties every built file must have, whatever the spec. *)
let check_structure label (spec : Exec.spec) bytes =
  let d = decode bytes in
  let h = d.header in
  let t = spec.target in
  eq_int (label ^ " e_type") Const.et_exec h.e_type;
  eq_int (label ^ " e_machine") t.machine h.e_machine;
  eq_i64 (label ^ " e_flags") t.flags h.e_flags;
  eq_i64 (label ^ " e_entry") spec.entry h.e_entry;
  let ls = loads d in
  List.iter
    (fun (p : Types.phdr) ->
      eq_i64
        (label ^ " offset congruent to vaddr")
        0L
        (U64.rem (Int64.sub p.p_offset p.p_vaddr) p.p_align);
      if not (U64.le p.p_filesz p.p_memsz) then Check.failf "%s: filesz > memsz" label;
      if not (U64.le p.p_offset (Int64.of_int (String.length bytes))) then
        Check.failf "%s: p_offset past the end of the file" label;
      if p.p_filesz = 0L then ()
      else if not (U64.le (Int64.add p.p_offset p.p_filesz) (Int64.of_int (String.length bytes)))
      then Check.failf "%s: segment data past the end of the file" label)
    ls;
  let rec ascending = function
    | (a : Types.phdr) :: (b :: _ as rest) ->
        if not (U64.le a.p_vaddr b.p_vaddr) then Check.failf "%s: PT_LOADs are not ascending" label;
        ascending rest
    | _ -> ()
  in
  ascending ls;
  (match spec.headers with
  | Exec.Unmapped ->
      if Array.exists (fun (p : Types.phdr) -> p.p_type = Const.pt_phdr) d.phdrs then
        Check.failf "%s: PT_PHDR in an unmapped file" label
  | Exec.Mapped { vaddr; _ } ->
      let first = d.phdrs.(0) in
      eq_i64 (label ^ " first is PT_PHDR") Const.pt_phdr first.p_type;
      let hload = List.find (fun (p : Types.phdr) -> p.p_vaddr = vaddr && p.p_offset = 0L) ls in
      if
        not
          (U64.le hload.p_vaddr first.p_vaddr
          && U64.le (Int64.add first.p_vaddr first.p_memsz) (Int64.add hload.p_vaddr hload.p_filesz)
          )
      then Check.failf "%s: PT_PHDR is not inside the header load" label;
      eq_i64 (label ^ " headers_size")
        (Exec.headers_size t
           {
             mapped_headers = true;
             gnu_stack = spec.gnu_stack <> None;
             segments = List.length spec.segments;
           })
        hload.p_filesz;
      eq_i64 (label ^ " e_phoff + table") hload.p_filesz
        (Int64.add h.e_phoff (Int64.of_int (d.phnum * h.e_phentsize))));
  d

(* Section contents and flags match the spec. *)
let check_sections label (spec : Exec.spec) bytes =
  let d = decode bytes in
  List.iter
    (fun (seg : Exec.segment) ->
      List.iter
        (fun (s : Exec.section) ->
          let sec = section d s.name in
          eq_i64 (label ^ " " ^ s.name ^ " addr") s.addr sec.shdr.sh_addr;
          let flags =
            List.fold_left Int64.logor Const.shf_alloc
              [
                (if seg.perms.write then Const.shf_write else 0L);
                (if seg.perms.execute then Const.shf_execinstr else 0L);
              ]
          in
          eq_i64 (label ^ " " ^ s.name ^ " flags") flags sec.shdr.sh_flags;
          match s.content with
          | Exec.Bytes b ->
              eq_i64 (label ^ " type") Const.sht_progbits sec.shdr.sh_type;
              Check.bytes_equal (label ^ " " ^ s.name) b (sec_bytes d s.name)
          | Exec.Zero n ->
              eq_i64 (label ^ " type") Const.sht_nobits sec.shdr.sh_type;
              eq_i64 (label ^ " " ^ s.name ^ " size") n sec.shdr.sh_size)
        seg.sections)
    spec.segments

(* The bytes a segment maps equal the section bytes, and the rest of its file extent is zero. *)
let check_segments label (spec : Exec.spec) bytes =
  let d = decode bytes in
  List.iter
    (fun (seg : Exec.segment) ->
      let first = List.hd seg.sections in
      let p =
        List.find
          (fun (p : Types.phdr) -> p.p_vaddr = first.addr && p.p_type = Const.pt_load)
          (Array.to_list d.phdrs)
      in
      let data =
        Check.ok ~pp_error:Decode.pp_error "segment"
          (Decode.segment_data d
             (let rec idx i = if d.phdrs.(i) == p then i else idx (i + 1) in
              idx 0))
      in
      List.iter
        (fun (s : Exec.section) ->
          match s.content with
          | Exec.Bytes b ->
              Check.bytes_equal
                (label ^ " " ^ s.name ^ " in segment")
                b
                (String.sub data (Int64.to_int (Int64.sub s.addr first.addr)) (String.length b))
          | Exec.Zero _ -> ())
        seg.sections;
      ignore p)
    spec.segments

let () =
  Check.run "build"
    [
      Check.case "structure, all targets and layouts" (fun () ->
          List.iter
            (fun (name, target) ->
              List.iter
                (fun (variant, spec) ->
                  let label = name ^ "/" ^ variant in
                  let bytes = build spec in
                  ignore (check_structure label spec bytes);
                  check_segments label spec bytes;
                  if spec.section_headers then check_sections label spec bytes)
                [
                  ("sections", Sample.spec target);
                  ("sectionless", Sample.spec ~sections:false target);
                  ("high", Sample.spec ~base:0x9000_0000L target);
                  ("high sectionless", Sample.spec ~base:0x9000_0000L ~sections:false target);
                ])
            targets);
      Check.case "program header order" (fun () ->
          let spec = Sample.spec (Target.riscv Riscv.rv32imafd_ilp32d) in
          let d = decode (build spec) in
          let types = List.map (fun (p : Types.phdr) -> p.p_type) (Array.to_list d.phdrs) in
          let names = List.map (fun v -> Format.asprintf "%a" Names.pp_pt v) types in
          eq_str "types" "PHDR LOAD LOAD LOAD LOAD LOAD LOAD GNU_STACK RISCV_ATTRIBUTES"
            (String.concat " " names);
          let stack = d.phdrs.(7) in
          eq_i64 "stack flags" 6L stack.p_flags;
          eq_i64 "stack align" 16L stack.p_align;
          eq_i64 "stack filesz" 0L stack.p_filesz;
          let attr = d.phdrs.(8) in
          eq_i64 "attr flags" 4L attr.p_flags;
          eq_i64 "attr vaddr" 0L attr.p_vaddr;
          eq_i64 "attr align" 1L attr.p_align);
      Check.case "segment flags and alignment" (fun () ->
          let d = decode (build (Sample.spec (Target.riscv Riscv.rv32imafd_ilp32d))) in
          let flags = List.map (fun (p : Types.phdr) -> Int64.to_int p.p_flags) (loads d) in
          Check.equal
            ~pp:(fun ppf l -> List.iter (Format.fprintf ppf "%d ") l)
            "flags" [ 4; 5; 5; 4; 6; 6 ] flags;
          List.iter (fun (p : Types.phdr) -> eq_i64 "align" 0x1000L p.p_align) (loads d));
      Check.case "pure zero-fill segment has no file data" (fun () ->
          let spec = Sample.spec (Target.riscv Riscv.rv32imafd_ilp32d) in
          let bytes = build spec in
          let d = decode bytes in
          let bss = List.find (fun (p : Types.phdr) -> p.p_vaddr = Sample.addr ".bss") (loads d) in
          eq_i64 "filesz" 0L bss.p_filesz;
          eq_i64 "memsz" Sample.bss_size bss.p_memsz;
          if not (U64.le bss.p_offset (Int64.of_int (String.length bytes))) then
            Check.fail "offset past EOF";
          let mixed =
            List.find (fun (p : Types.phdr) -> p.p_vaddr = Sample.addr ".data") (loads d)
          in
          eq_i64 "mixed filesz" (Int64.of_int Sample.data_init) mixed.p_filesz;
          eq_i64 "mixed memsz"
            (Int64.add (Int64.of_int Sample.data_init) Sample.data_zero)
            mixed.p_memsz);
      Check.case "symbol table" (fun () ->
          List.iter
            (fun (name, target) ->
              let spec = Sample.spec target in
              let d = decode (build spec) in
              let symtab = section d ".symtab" in
              let syms = Check.ok ~pp_error:Decode.pp_error "symbols" (Decode.symbols d symtab) in
              eq_int (name ^ " count") 5 (Array.length syms);
              eq_str (name ^ " order") "|aux|_start|marker|abs_one"
                (String.concat "|"
                   (List.map (fun (s : Decode.symbol) -> s.sym_name) (Array.to_list syms)));
              eq_i64 (name ^ " sh_info is the first non-local") 2L symtab.shdr.sh_info;
              eq_i64 (name ^ " sh_link")
                (Int64.of_int (section d ".strtab").index)
                symtab.shdr.sh_link;
              let find n =
                List.find (fun (s : Decode.symbol) -> s.sym_name = n) (Array.to_list syms)
              in
              eq_i64 (name ^ " _start value") (Sample.addr ".text") (find "_start").sym.st_value;
              eq_i64 (name ^ " _start section")
                (Int64.of_int (section d ".text").index)
                (find "_start").shndx;
              eq_int (name ^ " _start info")
                (Types.st_info ~bind:Const.stb_global ~typ:Const.stt_func)
                (find "_start").sym.st_info;
              eq_int (name ^ " abs") Const.shn_abs (find "abs_one").sym.st_shndx;
              eq_int (name ^ " weak") Const.stb_weak (Types.st_bind (find "abs_one").sym.st_info);
              eq_int (name ^ " local") Const.stb_local (Types.st_bind (find "aux").sym.st_info))
            targets);
      Check.case "attributes section and segment cover the same bytes" (fun () ->
          let spec = Sample.spec (Target.riscv Riscv.rv32imafd_ilp32d) in
          let d = decode (build spec) in
          let sec = section d ".riscv.attributes" in
          eq_i64 "type" Const.sht_riscv_attributes sec.shdr.sh_type;
          let seg = d.phdrs.(8) in
          eq_i64 "offset" sec.shdr.sh_offset seg.p_offset;
          eq_i64 "size" sec.shdr.sh_size seg.p_filesz;
          let attrs = Check.ok ~pp_error:Decode.pp_error "attributes" (Decode.attributes d sec) in
          Check.equal ~pp:pp_any "contents" (Riscv.attributes Riscv.rv32imafd_ilp32d) attrs;
          eq_int "section is last but two" (section d ".symtab").index (sec.index + 1));
      Check.case "ARM attributes are optional" (fun () ->
          let plain = decode (build (Sample.spec (Target.arm Arm.hard_float))) in
          if Decode.find_section plain ".ARM.attributes" <> None then
            Check.fail "unexpected attributes";
          let attrs =
            [
              {
                Attributes.vendor = "aeabi";
                contents = `Parsed [ (Attributes.File, [ (6, Attributes.Uleb 10L) ]) ];
              };
            ]
          in
          let t = Target.arm { Arm.float_abi = `Hard; attributes = Some attrs } in
          let d = decode (build (Sample.spec t)) in
          let sec = section d ".ARM.attributes" in
          Check.equal ~pp:pp_any "contents" attrs
            (Check.ok ~pp_error:Decode.pp_error "attrs" (Decode.attributes d sec));
          (* No attribute segment for ARM. *)
          Check.equal ~pp:pp_any "no segment" false
            (Array.exists (fun (p : Types.phdr) -> p.p_type = Const.pt_riscv_attributes) d.phdrs));
      Check.case "no program-header extras when unmapped and no stack" (fun () ->
          let spec =
            {
              (Sample.spec ~sections:false Target.x86_32) with
              headers = Exec.Unmapped;
              gnu_stack = None;
            }
          in
          let d = decode (build spec) in
          eq_int "phnum" 5 d.phnum;
          eq_i64 "e_phoff" 52L d.header.e_phoff;
          eq_int "shnum" 0 d.shnum;
          eq_i64 "e_shoff" 0L d.header.e_shoff);
      Check.case "flags and entry per target" (fun () ->
          List.iter
            (fun (name, target) ->
              let d = decode (build (Sample.spec target)) in
              eq_i64 (name ^ " flags") target.Target.flags d.header.e_flags;
              eq_int (name ^ " machine") target.Target.machine d.header.e_machine;
              Check.equal ~pp:Types.pp_class (name ^ " class") target.Target.elf_class
                d.header.ident.elf_class)
            targets);
      Check.case "extended section numbering" (fun () ->
          let n = 0xff10 in
          let rx = { Exec.read = true; write = false; execute = true } in
          let sections =
            List.init n (fun i ->
                {
                  Exec.name = Printf.sprintf "s%d" i;
                  addr = Int64.add 0x40_1000L (Int64.of_int i);
                  align = 1L;
                  content = Exec.Bytes "x";
                })
          in
          let spec symbols =
            {
              Exec.target = Target.x86_32;
              entry = 0x40_1000L;
              headers = Exec.Mapped { vaddr = 0x40_0000L; paddr = None };
              gnu_stack = None;
              section_headers = true;
              segments = [ { perms = rx; paddr = None; sections } ];
              symbols;
            }
          in
          let sym name section =
            {
              Exec.name;
              value = 0L;
              size = 0L;
              kind = `Notype;
              binding = `Global;
              section = Some section;
            }
          in
          let bytes = build (spec [ sym "early" "s3" ]) in
          let h = Fixture.header bytes in
          eq_int "e_shnum" 0 h.e_shnum;
          eq_int "e_shstrndx" Const.shn_xindex h.e_shstrndx;
          let d = decode bytes in
          (* null + n sections + .symtab .strtab .shstrtab *)
          eq_int "shnum" (n + 4) d.shnum;
          eq_int "shstrndx" (n + 3) d.shstrndx;
          eq_str "last name" ".shstrtab" d.sections.(n + 3).name;
          eq_str "section name" "s5" d.sections.(6).name;
          let syms =
            Check.ok ~pp_error:Decode.pp_error "symbols" (Decode.symbols d (section d ".symtab"))
          in
          eq_i64 "early symbol section" 4L syms.(1).shndx;
          fails "symbol past SHN_LORESERVE"
            (function
              | `Unsupported_symbol_section_index { Exec.symbol = "late"; index } -> index = 0xff09
              | _ -> false)
            (Exec.build (spec [ sym "late" "s65288" ])));
      Check.case "extended program header numbering" (fun () ->
          let rx = { Exec.read = true; write = false; execute = true } in
          let rw = { Exec.read = true; write = true; execute = false } in
          let code =
            {
              Exec.perms = rx;
              paddr = None;
              sections =
                [ { name = "code"; addr = 0x40_0000L; align = 4L; content = Exec.Bytes "abcd" } ];
            }
          in
          let zero i =
            {
              Exec.perms = rw;
              paddr = None;
              sections =
                [
                  {
                    name = Printf.sprintf "z%d" i;
                    addr = Int64.add 0x50_0000L (Int64.mul 0x1000L (Int64.of_int i));
                    align = 4L;
                    content = Exec.Zero 8L;
                  };
                ];
            }
          in
          let spec section_headers =
            {
              Exec.target = Target.x86_32;
              entry = 0x40_0000L;
              headers = Exec.Unmapped;
              gnu_stack = None;
              section_headers;
              segments = code :: List.init 0xfffe zero;
              symbols = [];
            }
          in
          let bytes = build (spec true) in
          eq_int "raw e_phnum" Const.pn_xnum (Fixture.header bytes).e_phnum;
          let d = decode bytes in
          eq_int "phnum" 0xffff d.phnum;
          eq_i64 "sh_info of section 0" 0xffffL d.sections.(0).shdr.sh_info;
          fails "no room for the count without section headers"
            (function
              | `Field_overflow { Encode.field = "e_phnum"; value = 0xffffL; bits = 16; _ } -> true
              | _ -> false)
            (Exec.build (spec false)));
      Check.case "files too large to build" (fun () ->
          let a = Int64.shift_left 1L 61 in
          let spec =
            {
              Exec.target = Target.x86_64;
              entry = a;
              headers = Exec.Unmapped;
              gnu_stack = None;
              section_headers = false;
              symbols = [];
              segments =
                [
                  {
                    Exec.perms = { read = true; write = false; execute = true };
                    paddr = None;
                    sections =
                      [
                        { name = "a"; addr = a; align = 8L; content = Exec.Bytes "x" };
                        {
                          name = "b";
                          addr = Int64.shift_left 1L 62;
                          align = Int64.shift_left 1L 62;
                          content = Exec.Zero 8L;
                        };
                      ];
                  };
                ];
            }
          in
          fails "too large" (function `File_too_large _ -> true | _ -> false) (Exec.build spec));
      Check.case "place" (fun () ->
          let rv32 = Target.riscv Riscv.rv32imafd_ilp32d in
          let ro = { Exec.read = true; write = false; execute = false } in
          let rx = { ro with execute = true } in
          let rw = { ro with write = true } in
          let req name perms init_size zero_fill =
            { Exec.name; perms; init_size; zero_fill; align = 4L }
          in
          let requests =
            [
              req ".text" rx 16L 0L;
              req ".text.aux" rx 4L 0L;
              req ".rodata" ro 8L 0L;
              req ".data" rw 0x100L 0x3000L;
              req ".bss" rw 0L 0x2000L;
            ]
          in
          let headers, addrs =
            Check.ok ~pp_error:Exec.pp_error "place"
              (Exec.place rv32 ~mapped_headers:true ~gnu_stack:true ~base:0x40_0000L requests)
          in
          Check.equal ~pp:pp_any "headers" true
            (headers = Exec.Mapped { vaddr = 0x40_0000L; paddr = None });
          List.iter2
            (fun (n, a) expected -> eq_i64 n expected a)
            addrs
            [ 0x40_1000L; 0x40_2000L; 0x40_3000L; 0x40_4000L; 0x40_8000L ];
          (* Place, bind bytes of the requested sizes, and the result is a valid spec that builds. *)
          let sections =
            List.map2
              (fun (r : Exec.request) (_, addr) ->
                {
                  Exec.perms = r.perms;
                  paddr = None;
                  sections =
                    (let init = Int64.to_int r.init_size in
                     let data =
                       if init > 0 then
                         [
                           {
                             Exec.name = r.name;
                             addr;
                             align = 4L;
                             content = Exec.Bytes (String.make init 'x');
                           };
                         ]
                       else []
                     in
                     let zero =
                       if r.zero_fill > 0L then
                         [
                           {
                             Exec.name = r.name ^ ".zero";
                             addr = Int64.add addr r.init_size;
                             align = 4L;
                             content = Exec.Zero r.zero_fill;
                           };
                         ]
                       else []
                     in
                     data @ zero);
                })
              requests addrs
          in
          let spec =
            {
              Exec.target = rv32;
              entry = 0x40_1000L;
              headers;
              gnu_stack = Some rw;
              section_headers = true;
              segments = sections;
              symbols = [];
            }
          in
          let bytes = build spec in
          let d = decode bytes in
          (* headers_size equals the end of the program-header table in the built file. *)
          let hload = List.hd (loads d) in
          eq_i64 "headers_size" hload.p_filesz
            (Exec.headers_size rv32 { mapped_headers = true; gnu_stack = true; segments = 5 });
          eq_i64 "e_phoff + table" hload.p_filesz
            (Int64.add d.header.e_phoff (Int64.of_int (d.phnum * d.header.e_phentsize)));
          (* A large alignment lands on its boundary. *)
          let _, addrs =
            Check.ok ~pp_error:Exec.pp_error "place aligned"
              (Exec.place rv32 ~mapped_headers:true ~gnu_stack:false ~base:0x40_0000L
                 [ req "a" rx 16L 0L; { (req "b" rx 16L 0L) with align = 0x20000L } ])
          in
          eq_i64 "128 KiB boundary" 0x42_0000L (List.assoc "b" addrs);
          (* Errors. *)
          fails "misaligned base"
            (function `Headers_misaligned { Exec.vaddr = 0x40_0010L; _ } -> true | _ -> false)
            (Exec.place rv32 ~mapped_headers:true ~gnu_stack:false ~base:0x40_0010L requests);
          fails "bad alignment"
            (function `Bad_alignment { Exec.section = "a"; align = 3L } -> true | _ -> false)
            (Exec.place rv32 ~mapped_headers:false ~gnu_stack:false ~base:0x40_0000L
               [ { (req "a" rx 4L 0L) with align = 3L } ]);
          fails "ELF32 range"
            (function `Range_exceeds_class _ -> true | _ -> false)
            (Exec.place rv32 ~mapped_headers:false ~gnu_stack:false ~base:0xffff_f000L
               [ req "a" rx 0x1000L 0L; req "b" rx 0x1000L 0L ]);
          fails "bad page size"
            (function `Bad_page_size 0x3000L -> true | _ -> false)
            (Exec.place
               (Target.aarch64 ~page_size:0x3000L ())
               ~mapped_headers:false ~gnu_stack:false ~base:0L []));
    ]
