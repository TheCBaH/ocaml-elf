[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

(* Bare-metal matrix: the same payloads as run_user.ml, started on QEMU's standard machine for each
   architecture with no operating system. Each reports through the machine's exit device, and the
   startup contract per architecture is in design §7. *)

open Elf_test_support
open Elf
module T = Elf_gnu.Toolchain
module H = Elf_gnu.Harness

type matrix = {
  payload : (module Elf_gnu.Payload.S);
  base : int64;
  abis : (string * Target.t) list;
  long_mode : bool;  (** 64-bit code in an ELF32 Multiboot container *)
  pass : int;  (** exit status of a passing payload *)
  fail : int -> int;  (** exit status of a payload that fails check [code] *)
}

let arm_v7 (a : Arm.abi) = Target.arm { a with attributes = Some Arm.armv7a_attributes }

let matrices =
  let identity code = code in
  [
    {
      payload = Elf_gnu.Payload_riscv.make Target.Riscv32;
      base = 0x8000_0000L;
      abis =
        [
          ("ilp32d", Target.riscv Riscv.rv32imafd_ilp32d); ("ilp32", Target.riscv Riscv.rv32im_ilp32);
        ];
      long_mode = false;
      pass = 0;
      fail = identity;
    };
    {
      payload = Elf_gnu.Payload_riscv.make Target.Riscv64;
      base = 0x8000_0000L;
      abis =
        [ ("lp64d", Target.riscv Riscv.rv64imafd_lp64d); ("lp64", Target.riscv Riscv.rv64im_lp64) ];
      long_mode = false;
      pass = 0;
      fail = identity;
    };
    {
      (* isa-debug-exit: writing v exits with (v << 1) | 1, and a passing payload writes 21. *)
      payload = Elf_gnu.Payload_x86.make32;
      base = 0x10_0000L;
      abis = [ ("default", Target.x86_32) ];
      long_mode = false;
      pass = 43;
      fail = (fun code -> (code lsl 1) lor 1);
    };
    {
      (* QEMU's Multiboot loader rejects ELF64, so the x86-64 payload is wrapped in an ELF32
         container (an x86-32 target) whose entry code switches to long mode (design §7). *)
      payload = Elf_gnu.Payload_x86.make64;
      base = 0x10_0000L;
      abis = [ ("long-mode", Target.x86_32) ];
      long_mode = true;
      pass = 43;
      fail = (fun code -> (code lsl 1) lor 1);
    };
    {
      payload = Elf_gnu.Payload_aarch64.make;
      base = 0x4010_0000L;
      abis = [ ("default", Target.aarch64 ()) ];
      long_mode = false;
      pass = 0;
      fail = identity;
    };
    {
      payload = Elf_gnu.Payload_arm.make;
      base = 0x4010_0000L;
      abis = [ ("hard", arm_v7 Arm.hard_float); ("soft", arm_v7 Arm.soft_float) ];
      long_mode = false;
      pass = 0;
      fail = identity;
    };
  ]

let name_of arch (v : Elf_gnu.Spec.variant) control =
  Printf.sprintf "system-%s-%s-%Lx%s%s"
    (Format.asprintf "%a" Target.pp_arch arch)
    v.abi v.base
    (if v.sections then "-sections" else "-bare")
    (match control with
    | `None -> ""
    | `Flip_rodata -> "-flip"
    | `Dirty_zero_fill -> "-dirty"
    | `Illegal_instruction -> "-trap")

let expect_status ~long_mode ~payload ~target ~variant ~control ~expected =
  let (module P : Elf_gnu.Payload.S) = payload in
  let name = name_of P.arch variant control in
  match H.build ~kind:`System ~long_mode payload ~name ~target ~variant ~control with
  | Error (`Missing tool) -> T.skip_or_fail tool
  | Ok (tools, spec, exec, dir, text, aux) -> (
      if control = `None then Elf_gnu.Structural.check tools spec exec ~dir ~text ~aux;
      match tools.qemu_system with
      | Some qemu when T.have qemu ->
          let r = H.run_system tools P.arch ~dir (Filename.concat dir "prog") in
          Check.equal ~pp:Format.pp_print_int (name ^ " exit status") expected r.status
      | Some qemu -> T.skip_or_fail qemu
      | None -> T.skip_or_fail "qemu-system")

let cases (m : matrix) =
  let (module P : Elf_gnu.Payload.S) = m.payload in
  let variants =
    List.concat_map
      (fun sections ->
        List.map
          (fun (abi, target) -> ({ Elf_gnu.Spec.base = m.base; sections; abi }, target))
          m.abis)
      [ true; false ]
  in
  List.map
    (fun (v, target) ->
      Check.case (name_of P.arch v `None) (fun () ->
          expect_status ~long_mode:m.long_mode ~payload:m.payload ~target ~variant:v ~control:`None
            ~expected:m.pass))
    variants
  @ List.map
      (fun (control, code) ->
        let abi, target = List.hd m.abis in
        let v = { Elf_gnu.Spec.base = m.base; sections = true; abi } in
        Check.case (name_of P.arch v control) (fun () ->
            expect_status ~long_mode:m.long_mode ~payload:m.payload ~target ~variant:v ~control
              ~expected:(m.fail code)))
      [ (`Flip_rodata, 11); (`Dirty_zero_fill, 13); (`Illegal_instruction, 0x7f) ]

let () = Check.run "run_system" (List.concat_map cases matrices)
