[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

open Elf_test_support
open Elf

let pp_i64 ppf v = Format.fprintf ppf "0x%Lx" v
let eq_i64 what e a = Check.equal ~pp:pp_i64 what e a
let eq_int what e a = Check.equal ~pp:Format.pp_print_int what e a
let eq_str what e a = Check.equal ~pp:Format.pp_print_string what e a
let eq_class what e a = Check.equal ~pp:Types.pp_class what e a

let row name (t : Target.t) ~cls ~machine ~flags ~page =
  eq_class (name ^ " class") cls t.elf_class;
  eq_int (name ^ " machine") machine t.machine;
  eq_i64 (name ^ " flags") flags t.flags;
  eq_i64 (name ^ " page") page t.max_page_size;
  Check.equal ~pp:Types.pp_endianness (name ^ " endianness") Types.Little t.endianness;
  eq_int (name ^ " osabi") 0 t.osabi

let () =
  let kib n = Int64.mul (Int64.of_int n) 1024L in
  Check.run "target"
    [
      Check.case "profiles, row by row" (fun () ->
          row "rv32"
            (Target.riscv Riscv.rv32imafd_ilp32d)
            ~cls:Types.Elf32 ~machine:243 ~flags:0x4L ~page:(kib 4);
          row "rv64"
            (Target.riscv Riscv.rv64imafd_lp64d)
            ~cls:Types.Elf64 ~machine:243 ~flags:0x4L ~page:(kib 4);
          row "x86-32" Target.x86_32 ~cls:Types.Elf32 ~machine:3 ~flags:0L ~page:(kib 4);
          row "x86-64" Target.x86_64 ~cls:Types.Elf64 ~machine:62 ~flags:0L ~page:(kib 4);
          row "arm hard" (Target.arm Arm.hard_float) ~cls:Types.Elf32 ~machine:40
            ~flags:0x0500_0400L ~page:(kib 4);
          row "arm soft" (Target.arm Arm.soft_float) ~cls:Types.Elf32 ~machine:40
            ~flags:0x0500_0200L ~page:(kib 4);
          row "aarch64" (Target.aarch64 ()) ~cls:Types.Elf64 ~machine:183 ~flags:0L ~page:(kib 64);
          row "aarch64 4k"
            (Target.aarch64 ~page_size:(kib 4) ())
            ~cls:Types.Elf64 ~machine:183 ~flags:0L ~page:(kib 4));
      Check.case "attributes per target" (fun () ->
          let attrs (t : Target.t) = t.attributes in
          let none what t =
            Check.equal
              ~pp:(fun ppf _ -> Format.pp_print_string ppf "<attrs>")
              what true
              (attrs t = None)
          in
          none "x86-32" Target.x86_32;
          none "x86-64" Target.x86_64;
          none "aarch64" (Target.aarch64 ());
          none "arm" (Target.arm Arm.hard_float);
          (match (Target.riscv Riscv.rv32imafd_ilp32d).attributes with
          | None -> Check.fail "riscv has attributes"
          | Some a ->
              eq_str "section" ".riscv.attributes" a.section_name;
              eq_i64 "section type" 0x7000_0003L a.section_type;
              Check.equal
                ~pp:(fun ppf -> function
                  | None -> Format.pp_print_string ppf "none" | Some v -> pp_i64 ppf v)
                "segment type" (Some 0x7000_0003L) a.segment_type);
          let arm_attrs =
            [
              {
                Attributes.vendor = "aeabi";
                contents = `Parsed [ (Attributes.File, [ (6, Attributes.Uleb 10L) ]) ];
              };
            ]
          in
          match (Target.arm { Arm.float_abi = `Hard; attributes = Some arm_attrs }).attributes with
          | None -> Check.fail "arm attributes expected"
          | Some a ->
              eq_str "arm section" ".ARM.attributes" a.section_name;
              eq_i64 "arm section type" 0x7000_0003L a.section_type;
              Check.equal
                ~pp:(fun ppf _ -> Format.pp_print_string ppf "<none>")
                "no segment" true (a.segment_type = None));
      Check.case "ident follows the profile" (fun () ->
          let id = Target.ident (Target.riscv Riscv.rv64im_lp64) in
          eq_class "class" Types.Elf64 id.elf_class;
          Check.equal ~pp:Types.pp_endianness "endianness" Types.Little id.endianness);
      Check.case "arch names" (fun () ->
          List.iter
            (fun a ->
              let name = Format.asprintf "%a" Target.pp_arch a in
              Check.equal
                ~pp:(fun ppf _ -> Format.pp_print_string ppf name)
                name true
                (Target.arch_of_string name = Some a))
            Target.all;
          Check.equal
            ~pp:(fun ppf _ -> Format.pp_print_string ppf "?")
            "unknown" true
            (Target.arch_of_string "mips" = None));
      Check.case "RISC-V e_flags, all 32 combinations" (fun () ->
          (* The psABI bit values, written out independently of Riscv.flags. *)
          List.iter
            (fun (fa, fbits) ->
              List.iter
                (fun rvc ->
                  List.iter
                    (fun rve ->
                      List.iter
                        (fun tso ->
                          let abi = { Riscv.rv32imafd_ilp32d with float_abi = fa; rvc; rve; tso } in
                          let expected =
                            fbits
                            + (if rvc then 0x1 else 0)
                            + (if rve then 0x8 else 0)
                            + if tso then 0x10 else 0
                          in
                          eq_i64
                            (Printf.sprintf "float=%x rvc=%b rve=%b tso=%b" fbits rvc rve tso)
                            (Int64.of_int expected) (Riscv.flags abi))
                        [ false; true ])
                    [ false; true ])
                [ false; true ])
            Riscv.[ (Soft, 0x0); (Single, 0x2); (Double, 0x4); (Quad, 0x6) ]);
      Check.case "RISC-V attributes" (fun () ->
          let t = Riscv.attributes Riscv.rv32imafd_ilp32d in
          Check.equal
            ~pp:(fun ppf _ -> Format.pp_print_string ppf "?")
            "stack_align" true
            (Attributes.find t ~vendor:"riscv" ~tag:4 = Some (Attributes.Uleb 16L));
          Check.equal
            ~pp:(fun ppf _ -> Format.pp_print_string ppf "?")
            "arch" true
            (Attributes.find t ~vendor:"riscv" ~tag:5
            = Some (Attributes.Ntbs Riscv.rv32imafd_ilp32d.arch));
          Check.equal
            ~pp:(fun ppf _ -> Format.pp_print_string ppf "?")
            "no unaligned" true
            (Attributes.find t ~vendor:"riscv" ~tag:6 = None);
          let t = Riscv.attributes { Riscv.rv32im_ilp32 with unaligned_access = Some true } in
          Check.equal
            ~pp:(fun ppf _ -> Format.pp_print_string ppf "?")
            "unaligned" true
            (Attributes.find t ~vendor:"riscv" ~tag:6 = Some (Attributes.Uleb 1L));
          (* The attributes must encode. *)
          ignore
            (Check.ok ~pp_error:Attributes.pp_error "encode" (Attributes.encode Types.Little t)));
      Check.case "ISA string order" (fun () ->
          let v = (2, 0) in
          eq_str "GAS rv32imafd" "rv32i2p0_m2p0_a2p0_f2p0_d2p0_zmmul1p0_zaamo1p0_zalrsc1p0"
            (Riscv.isa_string Riscv.Rv32 ~base:(`I, v)
               [
                 ("zalrsc", (1, 0));
                 ("d", v);
                 ("zmmul", (1, 0));
                 ("a", v);
                 ("f", v);
                 ("zaamo", (1, 0));
                 ("m", v);
               ]);
          eq_str "all classes" "rv64i2p1_c2p0_zicsr2p0_zba1p0_sstc1p0_xfoo1p0"
            (Riscv.isa_string Riscv.Rv64
               ~base:(`I, (2, 1))
               [
                 ("xfoo", (1, 0));
                 ("sstc", (1, 0));
                 ("zba", (1, 0));
                 ("zicsr", (2, 0));
                 ("c", (2, 0));
               ]);
          eq_str "rv32e" "rv32e2p0" (Riscv.isa_string Riscv.Rv32 ~base:(`E, v) []));
    ]
