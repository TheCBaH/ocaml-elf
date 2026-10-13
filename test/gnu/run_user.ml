(* Linux user-mode matrix: assemble a payload, build an ET_EXEC around it with Exec, check it
   against readelf/objdump and run it under qemu-<arch>. One matrix per architecture; the
   negative controls prove the checks can fail. *)

open Elf_test_support
open Elf
module T = Elf_gnu.Toolchain
module H = Elf_gnu.Harness

type matrix = {
  payload : (module Elf_gnu.Payload.S);
  bases : int64 list;
  abis : (string * Target.t) list;  (** the ABI name selects the assembler flags and e_flags *)
}

let matrices =
  let low = 0x40_0000L in
  [
    {
      payload = Elf_gnu.Payload_riscv.make Target.Riscv32;
      bases = [ low; 0x9000_0000L ];
      abis =
        [
          ("ilp32d", Target.riscv Riscv.rv32imafd_ilp32d); ("ilp32", Target.riscv Riscv.rv32im_ilp32);
        ];
    };
    {
      payload = Elf_gnu.Payload_riscv.make Target.Riscv64;
      bases = [ low; 0x1_2000_0000L ];
      abis =
        [ ("lp64d", Target.riscv Riscv.rv64imafd_lp64d); ("lp64", Target.riscv Riscv.rv64im_lp64) ];
    };
    {
      payload = Elf_gnu.Payload_x86.make32;
      bases = [ low; 0x9000_0000L ];
      abis = [ ("default", Target.x86_32) ];
    };
    {
      payload = Elf_gnu.Payload_x86.make64;
      bases = [ low; 0x1_2000_0000L ];
      abis = [ ("default", Target.x86_64) ];
    };
    {
      payload = Elf_gnu.Payload_arm.make;
      bases = [ low; 0x9000_0000L ];
      abis =
        (* With attributes, objdump disassembles for ARMv7 rather than a baseline architecture. *)
        [
          ("hard", Target.arm { Arm.hard_float with attributes = Some Arm.armv7a_attributes });
          ("soft", Target.arm { Arm.soft_float with attributes = Some Arm.armv7a_attributes });
        ];
    };
    {
      payload = Elf_gnu.Payload_aarch64.make;
      bases = [ low; 0x1_2000_0000L ];
      abis = [ ("default", Target.aarch64 ()) ];
    };
  ]

let name_of arch (v : Elf_gnu.Spec.variant) control =
  Printf.sprintf "%s-%s-%Lx%s%s"
    (Format.asprintf "%a" Target.pp_arch arch)
    v.abi v.base
    (if v.sections then "-sections" else "-bare")
    (match control with
    | `None -> ""
    | `Flip_rodata -> "-flip"
    | `Dirty_zero_fill -> "-dirty"
    | `Illegal_instruction -> "-trap")

let expect_status ~payload ~target ~variant ~control ~expected =
  let (module P : Elf_gnu.Payload.S) = payload in
  let name = name_of P.arch variant control in
  match H.build payload ~name ~target ~variant ~control with
  | Error (`Missing tool) -> T.skip_or_fail tool
  | Ok (tools, spec, exec, dir, text, aux) ->
      if control = `None then Elf_gnu.Structural.check tools spec exec ~dir ~text ~aux;
      if not (T.have tools.qemu_user) then T.skip_or_fail tools.qemu_user
      else
        let r = H.run_user tools ~dir (Filename.concat dir "prog") in
        Check.equal ~pp:Format.pp_print_int (name ^ " exit status") expected r.status

let cases (m : matrix) =
  let (module P : Elf_gnu.Payload.S) = m.payload in
  let variants =
    List.concat_map
      (fun base ->
        List.concat_map
          (fun sections ->
            List.map (fun (abi, target) -> ({ Elf_gnu.Spec.base; sections; abi }, target)) m.abis)
          [ true; false ])
      m.bases
  in
  List.map
    (fun (v, target) ->
      Check.case (name_of P.arch v `None) (fun () ->
          expect_status ~payload:m.payload ~target ~variant:v ~control:`None ~expected:42))
    variants
  @ List.map
      (fun (control, expected) ->
        let abi, target = List.hd m.abis in
        let v = { Elf_gnu.Spec.base = List.hd m.bases; sections = true; abi } in
        Check.case (name_of P.arch v control) (fun () ->
            expect_status ~payload:m.payload ~target ~variant:v ~control ~expected))
      [ (`Flip_rodata, 11); (`Dirty_zero_fill, 13) ]

let () = Check.run "run_user" (List.concat_map cases matrices)
