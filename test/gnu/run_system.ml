(* Bare-metal matrix: the same payload as run_user.ml, started on the QEMU virt machine with no
   firmware, in M-mode at e_entry. It reports through the SiFive test device. *)

open Elf_test_support
open Elf
module T = Elf_gnu.Toolchain
module H = Elf_gnu.Harness

let name_of arch (v : Elf_gnu.Spec.variant) control =
  Printf.sprintf "system-%s-%s-%s%s%s"
    (Format.asprintf "%a" Target.pp_arch arch)
    v.abi (Printf.sprintf "%Lx" v.base)
    (if v.sections then "-sections" else "-bare")
    (match control with
    | `None -> ""
    | `Flip_rodata -> "-flip"
    | `Dirty_zero_fill -> "-dirty"
    | `Illegal_instruction -> "-trap")

let expect_status ~payload ~target ~variant ~control ~expected =
  let (module P : Elf_gnu.Payload.S) = payload in
  let name = name_of P.arch variant control in
  match H.build ~kind:`System payload ~name ~target ~variant ~control with
  | Error (`Missing tool) -> T.skip_or_fail tool
  | Ok (tools, spec, exec, dir, text, aux) -> (
      if control = `None then Elf_gnu.Structural.check tools spec exec ~dir ~text ~aux;
      match tools.qemu_system with
      | Some qemu when T.have qemu ->
          let r = H.run_system tools P.arch ~dir (Filename.concat dir "prog") in
          Check.equal ~pp:Format.pp_print_int (name ^ " exit status") expected r.status
      | Some qemu -> T.skip_or_fail qemu
      | None -> T.skip_or_fail "qemu-system")

let rv32_cases () =
  let payload = Elf_gnu.Payload_riscv.make Target.Riscv32 in
  let profile = function "ilp32" -> Riscv.rv32im_ilp32 | _ -> Riscv.rv32imafd_ilp32d in
  let variants =
    List.concat_map
      (fun sections ->
        List.map
          (fun abi -> { Elf_gnu.Spec.base = 0x8000_0000L; sections; abi })
          [ "ilp32d"; "ilp32" ])
      [ true; false ]
  in
  let target v = Target.riscv (profile v.Elf_gnu.Spec.abi) in
  List.map
    (fun v ->
      Check.case (name_of Target.Riscv32 v `None) (fun () ->
          expect_status ~payload ~target:(target v) ~variant:v ~control:`None ~expected:0))
    variants
  @ List.map
      (fun (control, expected) ->
        let v = { Elf_gnu.Spec.base = 0x8000_0000L; sections = true; abi = "ilp32d" } in
        Check.case (name_of Target.Riscv32 v control) (fun () ->
            expect_status ~payload ~target:(target v) ~variant:v ~control ~expected))
      [ (`Flip_rodata, 11); (`Dirty_zero_fill, 13); (`Illegal_instruction, 0x7f) ]

let () = Check.run "run_system" (rv32_cases ())
