[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

open Elf_test_support
open Elf
open Exec

let rv32 = Target.riscv Riscv.rv32imafd_ilp32d
let rv64 = Target.riscv Riscv.rv64imafd_lp64d
let pp_any ppf _ = Format.pp_print_string ppf "<value>"
let pp_i64 ppf v = Format.fprintf ppf "0x%Lx" v
let sample = Sample.spec rv32
let problems ?ram spec = match validate ?ram spec with Ok _ -> [] | Error e -> Err.Error.kind e
let show errs = String.concat "; " (List.map (fun e -> Format.asprintf "%a" pp_error e) errs)

(* The spec fails with exactly one error, and it satisfies [pred]. *)
let only ?ram what (pred : error -> bool) spec =
  match problems ?ram spec with
  | [ e ] -> if not (pred e) then Check.failf "%s: wrong error: %a" what pp_error e
  | [] -> Check.failf "%s: expected an error, the spec was accepted" what
  | errs -> Check.failf "%s: expected one error, got %d: %s" what (List.length errs) (show errs)

(* The first reported error satisfies [pred]; later ones may be consequences of it. *)
let first what (pred : error -> bool) spec =
  match problems spec with
  | e :: _ -> if not (pred e) then Check.failf "%s: wrong first error: %a" what pp_error e
  | [] -> Check.failf "%s: expected an error, the spec was accepted" what

let accepted ?ram what spec =
  match problems ?ram spec with [] -> () | errs -> Check.failf "%s: rejected: %s" what (show errs)

let map_segment i f (spec : spec) =
  { spec with segments = List.mapi (fun j s -> if i = j then f s else s) spec.segments }

let map_section i k f (spec : spec) =
  map_segment i
    (fun s -> { s with sections = List.mapi (fun j x -> if j = k then f x else x) s.sections })
    spec

let rx = { read = true; write = false; execute = true }

let text_only ?(headers = Unmapped) ?(gnu_stack = None) target addr size =
  {
    target;
    entry = addr;
    headers;
    gnu_stack;
    section_headers = false;
    symbols = [];
    segments =
      [
        {
          perms = rx;
          paddr = None;
          sections =
            [ { name = ".text"; addr; align = 4L; content = Bytes (String.make size '\x01') } ];
        };
      ];
  }

let () =
  Check.run "exec"
    [
      Check.case "the sample spec is valid for every target" (fun () ->
          List.iter
            (fun (name, target) -> accepted name (Sample.spec target))
            [
              ("rv32", rv32);
              ("rv64", rv64);
              ("x86-32", Target.x86_32);
              ("x86-64", Target.x86_64);
              ("arm", Target.arm Arm.hard_float);
              ("aarch64", Target.aarch64 ());
            ];
          accepted "no sections" (Sample.spec ~sections:false rv32);
          accepted "high base" (Sample.spec ~base:0x9000_0000L rv32);
          accepted "64-bit high base" (Sample.spec ~base:0x1_2000_0000L rv64));
      Check.case "section alignment" (fun () ->
          only "Bad_alignment"
            (function `Bad_alignment { section = ".text"; align = 3L } -> true | _ -> false)
            (map_section 0 0 (fun s -> { s with align = 3L }) sample);
          only "zero alignment"
            (function `Bad_alignment { align = 0L; _ } -> true | _ -> false)
            (map_section 0 0 (fun s -> { s with align = 0L }) sample);
          only "Section_misaligned"
            (function
              | `Section_misaligned { section = ".text.aux"; addr; align = 4L } ->
                  addr = Int64.add (Sample.addr ".text.aux") 2L
              | _ -> false)
            (map_section 1 0
               (fun s -> { s with addr = Int64.add s.addr 2L })
               { sample with entry = Sample.addr ".text" }));
      Check.case "Bad_page_size" (fun () ->
          only "page size"
            (function `Bad_page_size 0x3000L -> true | _ -> false)
            (Sample.spec (Target.aarch64 ~page_size:0x3000L ())));
      Check.case "Empty_segment" (fun () ->
          only "empty"
            (function `Empty_segment 5 -> true | _ -> false)
            {
              sample with
              segments = sample.segments @ [ { perms = rx; paddr = None; sections = [] } ];
            });
      Check.case "section order within a segment" (fun () ->
          let text =
            { name = "a"; addr = 0x50_0000L; align = 4L; content = Bytes (String.make 16 'x') }
          in
          let seg sections = { perms = rx; paddr = None; sections } in
          let spec sections = { (text_only rv32 0x50_0000L 16) with segments = [ seg sections ] } in
          only "overlap"
            (function
              | `Sections_overlap { segment = 0; first = "a"; second = "b" } -> true | _ -> false)
            (spec [ text; { text with name = "b"; addr = 0x50_0008L } ]);
          first "out of order"
            (function
              | `Sections_overlap { segment = 0; first = "b"; second = "a" } -> true | _ -> false)
            { (spec [ { text with name = "b"; addr = 0x50_0010L }; text ]) with entry = 0x50_0010L };
          accepted "adjacent" (spec [ text; { text with name = "b"; addr = 0x50_0010L } ]));
      Check.case "Data_after_zero_fill" (fun () ->
          let s name addr content = { name; addr; align = 4L; content } in
          only "data after zero"
            (function `Data_after_zero_fill { segment = 0; section = "d" } -> true | _ -> false)
            {
              (text_only rv32 0x50_0000L 16) with
              segments =
                [
                  {
                    perms = rx;
                    paddr = None;
                    sections =
                      [
                        s "c" 0x50_0000L (Bytes "abcd");
                        s "z" 0x50_0004L (Zero 4L);
                        s "d" 0x50_0008L (Bytes "efgh");
                      ];
                  };
                ];
            });
      Check.case "address range and class" (fun () ->
          accepted "ELF32 up to 2^32" (text_only rv32 0xffff_f000L 0x1000);
          only "ELF32 one byte past 2^32"
            (function
              | `Range_exceeds_class { range = `Vaddr 0; start = 0xffff_f000L; length = 0x1001L } ->
                  true
              | _ -> false)
            (text_only rv32 0xffff_f000L 0x1001);
          accepted "ELF32 at 0x80000000 and 0x90000000"
            {
              (text_only rv32 0x8000_0000L 16) with
              segments =
                [
                  {
                    perms = rx;
                    paddr = None;
                    sections =
                      [
                        {
                          name = "a";
                          addr = 0x8000_0000L;
                          align = 4L;
                          content = Bytes (String.make 16 'x');
                        };
                      ];
                  };
                  {
                    perms = rx;
                    paddr = None;
                    sections =
                      [
                        {
                          name = "b";
                          addr = 0x9000_0000L;
                          align = 4L;
                          content = Bytes (String.make 16 'y');
                        };
                      ];
                  };
                ];
            };
          accepted "ELF64 above 2^32" (text_only rv64 0x1_0000_0000L 16);
          first "ELF64 wrap"
            (function
              | `Range_exceeds_class
                  { range = `Vaddr 0; start = 0xffff_ffff_ffff_f000L; length = 0x2000L } ->
                  true
              | _ -> false)
            { (text_only rv64 0xffff_ffff_ffff_f000L 0x2000) with entry = 0xffff_ffff_ffff_f000L };
          only "physical range"
            (function
              | `Range_exceeds_class { range = `Paddr 0; start = 0xffff_f000L; _ } -> true
              | _ -> false)
            (map_segment 0
               (fun s -> { s with paddr = Some 0xffff_f000L })
               (text_only rv32 0x40_0000L 0x2000)));
      Check.case "Segments_share_page" (fun () ->
          let s name addr = { name; addr; align = 4L; content = Bytes (String.make 16 'x') } in
          only "same page"
            (function
              | `Segments_share_page { first = `Segment 0; second = `Segment 1; _ } -> true
              | _ -> false)
            {
              (text_only rv32 0x50_0000L 16) with
              segments =
                [
                  { perms = rx; paddr = None; sections = [ s "a" 0x50_0000L ] };
                  { perms = rx; paddr = None; sections = [ s "b" 0x50_0800L ] };
                ];
            };
          only "headers and a segment"
            (function
              | `Segments_share_page { first = `Headers; second = `Segment 0; _ } -> true
              | _ -> false)
            {
              (text_only rv32 0x50_0100L 16) with
              headers = Mapped { vaddr = 0x50_0000L; paddr = None };
            };
          accepted "next page"
            {
              (text_only rv32 0x50_0000L 16) with
              segments =
                [
                  { perms = rx; paddr = None; sections = [ s "a" 0x50_0000L ] };
                  { perms = rx; paddr = None; sections = [ s "b" 0x50_1000L ] };
                ];
            });
      Check.case "Physical_overlap" (fun () ->
          only "overlap"
            (function
              | `Physical_overlap { first = `Segment 0; second = `Segment 1 } -> true | _ -> false)
            (sample
            |> map_segment 0 (fun s -> { s with paddr = Some 0x10_0000L })
            |> map_segment 1 (fun s -> { s with paddr = Some 0x10_0002L }));
          accepted "distinct physical"
            (sample
            |> map_segment 0 (fun s -> { s with paddr = Some 0x10_0000L })
            |> map_segment 1 (fun s -> { s with paddr = Some 0x10_0010L })));
      Check.case "Outside_ram" (fun () ->
          let ram = riscv_virt_ram in
          accepted ~ram "inside" (Sample.spec ~base:0x8000_0000L rv32);
          accepted "no window, no check" (Sample.spec rv32);
          (* Every region of the low-address sample is outside the window. *)
          (match problems ~ram (Sample.spec rv32) with
          | `Outside_ram { where = `Headers; _ } :: _ as errs ->
              Check.equal ~pp:Format.pp_print_int "one per region" 6 (List.length errs)
          | errs -> Check.failf "unexpected: %s" (show errs));
          (* The last page of RAM is inside; one more byte is not. *)
          let last size = { (text_only rv32 0x87ff_f000L size) with headers = Unmapped } in
          accepted ~ram "last page" (last 0x1000);
          only ~ram "one byte past the end"
            (function
              | `Outside_ram { where = `Segment 0; paddr = 0x87ff_f000L; length = 0x1001L; _ } ->
                  true
              | _ -> false)
            (last 0x1001);
          (* The physical address is what counts: a high virtual address loaded into RAM is fine. *)
          accepted ~ram "paddr inside"
            (map_segment 0
               (fun s -> { s with paddr = Some 0x8000_0000L })
               (text_only rv32 0x40_0000L 16));
          only ~ram "paddr outside"
            (function
              | `Outside_ram { where = `Segment 0; paddr = 0x40_0000L; _ } -> true | _ -> false)
            (map_segment 0
               (fun s -> { s with paddr = Some 0x40_0000L })
               (text_only rv32 0x8000_0000L 16));
          only ~ram "headers outside"
            (function `Outside_ram { where = `Headers; _ } -> true | _ -> false)
            {
              (text_only rv32 0x8000_1000L 16) with
              headers = Mapped { vaddr = 0x7fff_f000L; paddr = None };
            });
      Check.case "Headers_misaligned" (fun () ->
          only "headers"
            (function
              | `Headers_misaligned { vaddr = 0x40_0010L; page = 0x1000L } -> true | _ -> false)
            { sample with headers = Mapped { vaddr = 0x40_0010L; paddr = None } });
      Check.case "Entry_not_executable" (fun () ->
          only "entry in rodata"
            (function `Entry_not_executable e -> e = Sample.addr ".rodata" | _ -> false)
            { sample with entry = Sample.addr ".rodata" };
          only "entry past the code"
            (function `Entry_not_executable _ -> true | _ -> false)
            { sample with entry = Int64.add (Sample.addr ".text") 16L };
          only "entry in zero fill of an executable segment"
            (function `Entry_not_executable _ -> true | _ -> false)
            (map_segment 0
               (fun s ->
                 {
                   s with
                   sections =
                     s.sections
                     @ [
                         {
                           name = ".bss.x";
                           addr = Int64.add (Sample.addr ".text") 16L;
                           align = 4L;
                           content = Zero 16L;
                         };
                       ];
                 })
               { sample with entry = Int64.add (Sample.addr ".text") 16L }));
      Check.case "names and symbols" (fun () ->
          only "duplicate section"
            (function `Duplicate_section ".text" -> true | _ -> false)
            (map_section 1 0 (fun s -> { s with name = ".text" }) (Sample.spec ~symbols:false rv32));
          only "reserved name"
            (function `Duplicate_section ".symtab" -> true | _ -> false)
            (map_section 1 0
               (fun s -> { s with name = ".symtab" })
               (Sample.spec ~symbols:false rv32));
          only "NUL in a section name"
            (function `Bad_name { kind = `Section; name = ".te\000xt" } -> true | _ -> false)
            (map_section 0 0
               (fun s -> { s with name = ".te\000xt" })
               (Sample.spec ~symbols:false rv32));
          only "NUL in a symbol name"
            (function `Bad_name { kind = `Symbol; _ } -> true | _ -> false)
            {
              sample with
              symbols =
                [
                  {
                    name = "a\000";
                    value = 0L;
                    size = 0L;
                    kind = `Notype;
                    binding = `Local;
                    section = None;
                  };
                ];
            };
          only "unknown symbol section"
            (function
              | `Unknown_symbol_section { symbol = "s"; section = ".nope" } -> true | _ -> false)
            {
              sample with
              symbols =
                [
                  {
                    name = "s";
                    value = 0L;
                    size = 0L;
                    kind = `Notype;
                    binding = `Local;
                    section = Some ".nope";
                  };
                ];
            };
          only "symbols without section headers"
            (function `Symbols_without_sections -> true | _ -> false)
            {
              (Sample.spec ~sections:false rv32) with
              symbols =
                [
                  {
                    name = "s";
                    value = 0L;
                    size = 0L;
                    kind = `Notype;
                    binding = `Local;
                    section = None;
                  };
                ];
            };
          (* Names the builder emits itself are free when there are no section headers. *)
          accepted "reserved names without section headers"
            (map_section 1 0
               (fun s -> { s with name = ".symtab" })
               (Sample.spec ~sections:false rv32)));
      Check.case "every problem is reported, in order" (fun () ->
          let spec =
            {
              sample with
              segments =
                (let segs = sample.segments in
                 List.mapi
                   (fun i (s : segment) ->
                     if i = 0 then
                       {
                         s with
                         sections =
                           List.map (fun (x : Exec.section) -> { x with align = 3L }) s.sections;
                       }
                     else s)
                   segs
                 @ [ { perms = rx; paddr = None; sections = [] } ]);
              symbols =
                [
                  {
                    name = "a\000";
                    value = 0L;
                    size = 0L;
                    kind = `Notype;
                    binding = `Local;
                    section = None;
                  };
                ];
            }
          in
          match problems spec with
          | [ `Bad_alignment _; `Empty_segment 5; `Bad_name { kind = `Symbol; _ } ] -> ()
          | errs -> Check.failf "unexpected problems: %s" (show errs));
      Check.case "build reports an invalid spec" (fun () ->
          Check.error ~pp:pp_any "invalid"
            (function `Invalid_spec [ `Empty_segment 5 ] -> true | _ -> false)
            (build
               {
                 sample with
                 segments = sample.segments @ [ { perms = rx; paddr = None; sections = [] } ];
               }));
      Check.case "phdr_count and headers_size" (fun () ->
          let shape = { mapped_headers = true; gnu_stack = true; segments = 5 } in
          Check.equal ~pp:Format.pp_print_int "rv32: 5 + 2 + 1 + attributes" 9
            (phdr_count rv32 shape);
          Check.equal ~pp:Format.pp_print_int "x86-32: no attribute segment" 8
            (phdr_count Target.x86_32 shape);
          Check.equal ~pp:Format.pp_print_int "unmapped" 5
            (phdr_count Target.x86_32 { shape with mapped_headers = false; gnu_stack = false });
          Check.equal ~pp:pp_i64 "rv32 size"
            (Int64.of_int (52 + (9 * 32)))
            (headers_size rv32 shape);
          Check.equal ~pp:pp_i64 "rv64 size"
            (Int64.of_int (64 + (9 * 56)))
            (headers_size rv64 shape));
    ]
