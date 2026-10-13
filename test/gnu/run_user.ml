(* Linux user-mode matrix: assemble a payload, build an ET_EXEC around it with Exec, check it
   against readelf/objdump and run it under qemu-<arch>. *)

open Elf_test_support
open Elf
module T = Elf_gnu.Toolchain
module H = Elf_gnu.Harness

let rv32_profile = function "ilp32" -> Riscv.rv32im_ilp32 | _ -> Riscv.rv32imafd_ilp32d

let name_of arch (v : Elf_gnu.Spec.variant) control =
  Printf.sprintf "%s-%s-%s%s%s"
    (Format.asprintf "%a" Target.pp_arch arch)
    v.abi (Printf.sprintf "%Lx" v.base)
    (if v.sections then "-sections" else "-bare")
    (match control with `None -> "" | `Flip_rodata -> "-flip" | `Dirty_zero_fill -> "-dirty")

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

let rv32_cases () =
  let payload = Elf_gnu.Payload_riscv.make Target.Riscv32 in
  let variants =
    List.concat_map
      (fun base ->
        List.concat_map
          (fun sections ->
            List.map (fun abi -> { Elf_gnu.Spec.base; sections; abi }) [ "ilp32d"; "ilp32" ])
          [ true; false ])
      [ 0x40_0000L; 0x9000_0000L ]
  in
  let target v = Target.riscv (rv32_profile v.Elf_gnu.Spec.abi) in
  List.map
    (fun v ->
      Check.case (name_of Target.Riscv32 v `None) (fun () ->
          expect_status ~payload ~target:(target v) ~variant:v ~control:`None ~expected:42))
    variants
  @ List.map
      (fun (control, expected) ->
        let v = { Elf_gnu.Spec.base = 0x40_0000L; sections = true; abi = "ilp32d" } in
        Check.case (name_of Target.Riscv32 v control) (fun () ->
            expect_status ~payload ~target:(target v) ~variant:v ~control ~expected))
      [ (`Flip_rodata, 11); (`Dirty_zero_fill, 13) ]

let () = Check.run "run_user" (rv32_cases ())
