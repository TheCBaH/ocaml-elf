[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

(* The named RISC-V profiles and the ISA-string builder against GNU as. *)

open Elf_test_support
open Elf
module T = Elf_gnu.Toolchain

let ok what r = Check.ok ~pp_error:Decode.pp_error what r

(* What GNU as 2.44 emits for each -march under each ISA specification: the explicit extension
   lists the profiles are made of. *)
let v20 = (2, 0)
let v21 = (2, 1)
let v22 = (2, 2)
let z = (1, 0)

let profiles =
  [
    ( "rv32imafd",
      "ilp32d",
      Target.Riscv32,
      Riscv.rv32imafd_ilp32d,
      [
        ( "2.2",
          Riscv.Rv32,
          (`I, v20),
          [
            ("m", v20); ("a", v20); ("f", v20); ("d", v20); ("zmmul", z); ("zaamo", z); ("zalrsc", z);
          ] );
        ( "20191213",
          Riscv.Rv32,
          (`I, v21),
          [
            ("m", v20);
            ("a", v21);
            ("f", v22);
            ("d", v22);
            ("zicsr", v20);
            ("zmmul", z);
            ("zaamo", z);
            ("zalrsc", z);
          ] );
      ] );
    ( "rv32im",
      "ilp32",
      Target.Riscv32,
      Riscv.rv32im_ilp32,
      [
        ("2.2", Riscv.Rv32, (`I, v20), [ ("m", v20); ("zmmul", z) ]);
        ("20191213", Riscv.Rv32, (`I, v21), [ ("m", v20); ("zmmul", z) ]);
      ] );
    ( "rv64imafd",
      "lp64d",
      Target.Riscv64,
      Riscv.rv64imafd_lp64d,
      [
        ( "2.2",
          Riscv.Rv64,
          (`I, v20),
          [
            ("m", v20); ("a", v20); ("f", v20); ("d", v20); ("zmmul", z); ("zaamo", z); ("zalrsc", z);
          ] );
        ( "20191213",
          Riscv.Rv64,
          (`I, v21),
          [
            ("m", v20);
            ("a", v21);
            ("f", v22);
            ("d", v22);
            ("zicsr", v20);
            ("zmmul", z);
            ("zaamo", z);
            ("zalrsc", z);
          ] );
      ] );
    ( "rv64im",
      "lp64",
      Target.Riscv64,
      Riscv.rv64im_lp64,
      [
        ("2.2", Riscv.Rv64, (`I, v20), [ ("m", v20); ("zmmul", z) ]);
        ("20191213", Riscv.Rv64, (`I, v21), [ ("m", v20); ("zmmul", z) ]);
      ] );
  ]

let write path data =
  let oc = open_out_bin path in
  output_string oc data;
  close_out oc

let test (march, mabi, arch, (profile : Riscv.abi), specs) =
  match T.find ~abi:mabi arch with
  | Error (`Missing tool) -> T.skip_or_fail tool
  | Ok tools ->
      let dir = T.artifacts ("isa-" ^ march) in
      let src = Filename.concat dir "empty.s" in
      write src "\t.text\n\tnop\n";
      List.iter
        (fun (spec, xlen, base, exts) ->
          let obj = Filename.concat dir (Printf.sprintf "empty-%s.o" spec) in
          let status, _, err =
            T.run
              [
                List.hd tools.as_;
                "-march=" ^ march;
                "-mabi=" ^ mabi;
                "-misa-spec=" ^ spec;
                src;
                "-o";
                obj;
              ]
          in
          if status <> 0 then Check.failf "%s %s: assembler failed: %s" march spec err;
          let data = Check.ok ~pp_error:Elf_unix.pp_error "read" (Elf_unix.read_file obj) in
          let d = ok "decode" (Decode.of_string data) in
          let attrs =
            ok "attributes"
              (Decode.attributes d (Option.get (Decode.find_section d ".riscv.attributes")))
          in
          let gas_arch =
            match Attributes.find attrs ~vendor:"riscv" ~tag:5 with
            | Some (Attributes.Ntbs s) -> s
            | _ -> Check.failf "%s %s: no Tag_RISCV_arch" march spec
          in
          (* The builder reproduces GAS's string from the explicit list, whatever the order. *)
          Check.equal ~pp:Format.pp_print_string
            (Printf.sprintf "%s under -misa-spec=%s: isa_string" march spec)
            gas_arch
            (Riscv.isa_string xlen ~base (List.rev exts));
          if spec = "2.2" then begin
            (* The profile follows GAS's default specification. *)
            Check.equal ~pp:Format.pp_print_string (march ^ " profile arch") gas_arch profile.arch;
            Check.equal
              ~pp:(fun ppf v -> Format.fprintf ppf "0x%Lx" v)
              (march ^ " e_flags") d.header.e_flags (Riscv.flags profile);
            (* GAS writes no Tag_RISCV_stack_align; the profile adds it (Tag 4). *)
            Check.equal
              ~pp:(fun ppf _ -> Format.pp_print_string ppf "?")
              (march ^ " no stack_align from GAS")
              true
              (Attributes.find attrs ~vendor:"riscv" ~tag:4 = None);
            Check.equal
              ~pp:(fun ppf _ -> Format.pp_print_string ppf "?")
              (march ^ " profile arch tag") true
              (Attributes.find (Riscv.attributes profile) ~vendor:"riscv" ~tag:5
              = Some (Attributes.Ntbs gas_arch))
          end)
        specs

let () =
  Check.run "isa"
    (List.map
       (fun ((march, mabi, _, _, _) as p) -> Check.case (march ^ "-" ^ mabi) (fun () -> test p))
       profiles)
