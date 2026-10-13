open Elf_test_support
open Elf
module T = Toolchain
module R = Readelf

let read path = Check.ok ~pp_error:Elf_unix.pp_error path (Elf_unix.read_file path)

let write path data =
  let oc = open_out_bin path in
  output_string oc data;
  close_out oc

let hex v = Printf.sprintf "0x%Lx" v

let objdump_machine (arch : Target.arch) =
  match arch with
  | X86_32 -> "i386"
  | X86_64 -> "i386:x86-64"
  | Arm -> "arm"
  | Aarch64 -> "aarch64"
  | Riscv32 -> "riscv:rv32"
  | Riscv64 -> "riscv:rv64"

(* What readelf prints for these fields, written out per architecture rather than derived from the
   library's own profile. *)
let machine_name (arch : Target.arch) =
  match arch with
  | X86_32 -> "Intel 80386"
  | X86_64 -> "Advanced Micro Devices X86-64"
  | Arm -> "ARM"
  | Aarch64 -> "AArch64"
  | Riscv32 | Riscv64 -> "RISC-V"

let e_flags (s : Spec.t) =
  match s.arch with
  | Riscv32 | Riscv64 -> ( match s.variant.abi with "ilp32d" | "lp64d" -> 0x4L | _ -> 0x0L)
  | Arm -> if s.variant.abi = "soft" then 0x0500_0200L else 0x0500_0400L
  | _ -> 0L

let riscv_arch = function
  | "ilp32d" -> "rv32i2p0_m2p0_a2p0_f2p0_d2p0_zmmul1p0_zaamo1p0_zalrsc1p0"
  | "ilp32" -> "rv32i2p0_m2p0_zmmul1p0"
  | "lp64d" -> "rv64i2p0_m2p0_a2p0_f2p0_d2p0_zmmul1p0_zaamo1p0_zalrsc1p0"
  | _ -> "rv64i2p0_m2p0_zmmul1p0"

let check (tools : T.tools) (s : Spec.t) (_ : Exec.spec) ~dir ~text ~aux =
  let prog = Filename.concat dir "prog" and obj = Filename.concat dir "payload.o" in
  let mismatches = ref [] in
  let expect what expected actual =
    if expected <> actual then
      mismatches := Printf.sprintf "%s: expected %s, got %s" what expected actual :: !mismatches
  in
  let readelf args =
    let status, out, err = T.run ((tools.readelf :: "-W" :: args) @ [ prog ]) in
    if status <> 0 then Check.failf "readelf %s failed: %s" (String.concat " " args) err;
    out
  in
  let is64 = s.target.elf_class = Types.Elf64 in
  let ehsize = if is64 then 64 else 52 and phentsize = if is64 then 56 else 32 in
  let riscv = s.arch = Riscv32 || s.arch = Riscv64 in
  let system = s.kind = `System in
  let multiboot = Spec.multiboot_header s in
  (* loads: five regions, plus a stack in system mode and a Multiboot header on x86; the headers;
     PHDR; GNU_STACK in user mode only; the RISC-V attributes *)
  let phnum =
    5
    + (if system then 1 else 0)
    + (if multiboot <> None then 1 else 0)
    + 1 + 1
    + (if system then 0 else 1)
    + if riscv then 1 else 0
  in
  let hsize = Int64.of_int (ehsize + (phnum * phentsize)) in
  let page = if s.arch = Aarch64 then 0x10000L else 0x1000L in
  (* Header. *)
  let h = R.header (readelf [ "-h" ]) in
  let field k = Option.value (List.assoc_opt k h) ~default:"<missing>" in
  expect "Class" (if is64 then "ELF64" else "ELF32") (field "Class");
  expect "Data" "2's complement, little endian" (field "Data");
  expect "Type" "EXEC (Executable file)" (field "Type");
  expect "Machine" (machine_name s.arch) (field "Machine");
  expect "Entry point address" (hex s.text) (field "Entry point address");
  expect "Flags"
    (hex (e_flags s))
    (match String.split_on_char ',' (field "Flags") with f :: _ -> String.trim f | [] -> "");
  expect "Number of program headers" (string_of_int phnum) (field "Number of program headers");
  (* Program headers. *)
  let segs = R.segments (readelf [ "-l" ]) in
  let len b = Int64.of_int (String.length b) in
  let load vaddr filesz memsz flags = ("LOAD", vaddr, filesz, memsz, flags, page) in
  let loads =
    [
      load s.variant.base hsize hsize "R";
      load s.text (len text) (len text) "R E";
      load s.aux (len aux) (len aux) "R E";
      load s.rodata 8L 8L "R";
      load s.data (Int64.of_int s.data_init) (Int64.add (Int64.of_int s.data_init) s.data_zero) "RW";
      load s.bss 0L s.bss_size "RW";
    ]
    @ (if system then
         [
           load s.stack 0L (Int64.add s.stack_size (if Spec.idt s <> None then 0x100L else 0L)) "RW";
         ]
       else [])
    @ match multiboot with Some a -> [ load a 12L 12L "R" ] | None -> []
  in
  (* PT_LOADs ascend by address. *)
  let loads =
    List.stable_sort (fun (_, a, _, _, _, _) (_, b, _, _, _, _) -> Int64.unsigned_compare a b) loads
  in
  let expected =
    ( "PHDR",
      Int64.add s.variant.base (Int64.of_int ehsize),
      Int64.of_int (phnum * phentsize),
      Int64.of_int (phnum * phentsize),
      "R",
      if is64 then 8L else 4L )
    :: loads
    @ if system then [] else [ ("GNU_STACK", 0L, 0L, 0L, "RW", 0x10L) ]
  in
  let row (p : R.segment) = (p.ptype, p.vaddr, p.filesz, p.memsz, p.pflags, p.palign) in
  let describe (t, v, f, m, fl, a) =
    Printf.sprintf "%s vaddr=%s filesz=%s memsz=%s flags=%S align=%s" t (hex v) (hex f) (hex m) fl
      (hex a)
  in
  let fixed = List.filteri (fun i _ -> i < List.length expected) segs in
  expect "program header count" (string_of_int phnum) (string_of_int (List.length segs));
  List.iteri
    (fun i e ->
      match List.nth_opt fixed i with
      | Some p -> expect (Printf.sprintf "program header %d" i) (describe e) (describe (row p))
      | None -> mismatches := Printf.sprintf "program header %d missing" i :: !mismatches)
    expected;
  if riscv then begin
    match List.nth_opt segs (List.length expected) with
    | Some p ->
        expect "attribute segment type" "RISCV_ATTRIBUT" p.ptype;
        expect "attribute segment flags" "R" p.pflags;
        expect "attribute segment align" "0x1" (hex p.palign)
    | None -> mismatches := "attribute segment missing" :: !mismatches
  end;
  (* Sections, symbols and attributes exist only in the sectioned variants. *)
  if s.variant.sections then begin
    let secs = R.sections (readelf [ "-S" ]) in
    let sec_expect name typ flags addr size =
      match List.find_opt (fun (x : R.section) -> x.name = name) secs with
      | None -> mismatches := Printf.sprintf "section %s missing" name :: !mismatches
      | Some x ->
          expect (name ^ " type") typ x.typ;
          expect (name ^ " flags") flags x.flags;
          expect (name ^ " addr") (hex addr) (hex x.addr);
          expect (name ^ " size") (hex size) (hex x.size)
    in
    sec_expect ".text" "PROGBITS" "AX" s.text (len text);
    sec_expect ".text.aux" "PROGBITS" "AX" s.aux (len aux);
    sec_expect ".rodata" "PROGBITS" "A" s.rodata 8L;
    sec_expect ".data" "PROGBITS" "WA" s.data (Int64.of_int s.data_init);
    sec_expect ".bss.data" "NOBITS" "WA" (Int64.add s.data (Int64.of_int s.data_init)) s.data_zero;
    sec_expect ".bss" "NOBITS" "WA" s.bss s.bss_size;
    if system then sec_expect ".stack" "NOBITS" "WA" s.stack s.stack_size;
    (match Spec.idt s with Some a -> sec_expect ".idt" "NOBITS" "WA" a 0x100L | None -> ());
    (match multiboot with Some a -> sec_expect ".mbhdr" "PROGBITS" "A" a 12L | None -> ());
    sec_expect ".symtab" "SYMTAB" "" 0L (Int64.of_int ((if is64 then 24 else 16) * 5));
    List.iter
      (fun n ->
        if not (List.exists (fun (x : R.section) -> x.name = n && x.typ = "STRTAB") secs) then
          mismatches := Printf.sprintf "no STRTAB section %s" n :: !mismatches)
      [ ".strtab"; ".shstrtab" ];
    let index name =
      match List.find_opt (fun (x : R.section) -> x.name = name) secs with
      | Some x -> string_of_int x.nr
      | None -> "<missing>"
    in
    let syms =
      match List.assoc_opt ".symtab" (R.symbols (readelf [ "-s" ])) with Some l -> l | None -> []
    in
    let sym_expect name typ value size section =
      match List.find_opt (fun (y : R.symbol) -> y.name = name) syms with
      | None -> mismatches := Printf.sprintf "symbol %s missing" name :: !mismatches
      | Some y ->
          expect (name ^ " type") typ y.typ;
          expect (name ^ " bind") "GLOBAL" y.bind;
          expect (name ^ " value") (hex value) (hex y.value);
          expect (name ^ " size") (hex size) (hex y.size);
          expect (name ^ " ndx") (index section) y.ndx
    in
    sym_expect "_start" "FUNC" s.text (len text) ".text";
    sym_expect "aux" "FUNC" s.aux (len aux) ".text.aux";
    sym_expect "rodata_marker" "OBJECT" s.rodata 4L ".rodata";
    sym_expect "data_marker" "OBJECT" s.data 4L ".data";
    if riscv then begin
      let attrs = R.attributes (readelf [ "-A" ]) in
      expect "Tag_RISCV_arch"
        (Printf.sprintf "%S" (riscv_arch s.variant.abi))
        (Option.value (List.assoc_opt "Tag_RISCV_arch" attrs) ~default:"<missing>");
      expect "Tag_RISCV_stack_align" "16-bytes"
        (Option.value (List.assoc_opt "Tag_RISCV_stack_align" attrs) ~default:"<missing>")
    end
  end;
  (* readelf's own consistency checks must be silent. *)
  (let status, _, err = T.run [ tools.readelf; "-W"; "--lint"; "-a"; prog ] in
   ignore status;
   if String.trim err <> "" then
     mismatches := Printf.sprintf "readelf --lint: stderr %S" err :: !mismatches);
  (* The code disassembles as it does in the object, at its new address. *)
  let object_code section =
    let _, out, _ = T.run [ tools.objdump; "-d"; "-j"; section; obj ] in
    Objdump.instructions ~vma:0L out
  in
  let compare_code what ~vma expected actual =
    if expected = [] then mismatches := (what ^ ": no instructions in the object") :: !mismatches
    else if expected <> actual then begin
      let rec first = function
        | e :: es, a :: as_ -> if e = a then first (es, as_) else Some (e, a)
        | _ -> None
      in
      let detail =
        match first (expected, actual) with
        | Some ((eb, et), (ab, at)) ->
            Printf.sprintf "; first difference: object %s %S, executable %s %S" eb et ab at
        | None -> ""
      in
      mismatches :=
        Printf.sprintf "%s: disassembly differs from the object's (vma %s; %d vs %d instructions)%s"
          what (hex vma) (List.length expected) (List.length actual) detail
        :: !mismatches
    end
  in
  List.iter
    (fun (obj_section, exe_section, vma, bytes) ->
      let expected = object_code obj_section in
      if s.variant.sections then begin
        let _, out, _ = T.run [ tools.objdump; "-d"; "-j"; exe_section; prog ] in
        compare_code exe_section ~vma expected (Objdump.instructions ~vma out)
      end
      else begin
        (* No section headers: take the segment bytes out of the file and disassemble them raw. *)
        let seg = List.find (fun (p : R.segment) -> p.vaddr = vma && p.ptype = "LOAD") segs in
        let data = String.sub (read prog) (Int64.to_int seg.p_offset) (Int64.to_int seg.filesz) in
        ignore bytes;
        let bin = Filename.concat dir (exe_section ^ ".bin") in
        write bin data;
        let _, out, _ =
          T.run
            [
              tools.objdump;
              "-b";
              "binary";
              "-m";
              objdump_machine s.arch;
              "-D";
              "--adjust-vma=" ^ hex vma;
              bin;
            ]
        in
        compare_code (exe_section ^ " (raw)") ~vma expected (Objdump.instructions ~vma out)
      end)
    [ (".text.main", ".text", s.text, text); (".text.aux", ".text.aux", s.aux, aux) ];
  match !mismatches with
  | [] -> ()
  | l -> Check.failf "structural checks:\n  %s" (String.concat "\n  " (List.rev l))
