open Elf_test_support
open Elf
module T = Toolchain

type run = { status : int; file : string; dir : string }

let write path data =
  let oc = open_out_bin path in
  output_string oc data;
  close_out oc

let ok pp what r = Check.ok ~pp_error:pp what r

(* No relocation section may apply to a payload section: GAS must have resolved everything. *)
let check_relocation_free name (d : Decode.t) payload_sections =
  Array.iter
    (fun (s : Decode.section) ->
      if s.shdr.sh_type = Const.sht_rel || s.shdr.sh_type = Const.sht_rela then
        let target = Int64.to_int s.shdr.sh_info in
        if target > 0 && target < d.shnum && List.mem d.sections.(target).name payload_sections then
          Check.failf
            "%s: %s applies to payload section %s; the payload must assemble without relocations"
            name s.name d.sections.(target).name)
    d.sections

let build ?(kind = `User) (module P : Payload.S) ~name ~target ~variant ~control =
  match T.find ~abi:variant.Spec.abi P.arch with
  | Error _ as e -> e
  | Ok tools ->
      let spec = Spec.make ~kind ~control target variant in
      let dir = T.artifacts name in
      let src = Filename.concat dir "payload.s" and obj = Filename.concat dir "payload.o" in
      write src (P.source spec);
      let status, _, err = T.run (tools.as_ @ [ src; "-o"; obj ]) in
      if status <> 0 then Check.failf "%s: assembler failed:\n%s" name err;
      let data = ok Elf_unix.pp_error "read object" (Elf_unix.read_file obj) in
      let d = ok Decode.pp_error "decode object" (Decode.of_string data) in
      check_relocation_free name d [ ".text.main"; ".text.aux" ];
      let section n =
        match Decode.find_section d n with
        | Some s -> ok Decode.pp_error n (Decode.section_data d s)
        | None -> Check.failf "%s: the object has no %s" name n
      in
      let text = section ".text.main" and aux = section ".text.aux" in
      let exec = Spec.exec_spec spec ~text ~aux in
      let prog = Filename.concat dir "prog" in
      let bytes = ok Exec.pp_error "build" (Exec.build ?ram:(Spec.ram spec) exec) in
      ok Elf_unix.pp_error "write" (Elf_unix.write_executable prog bytes);
      Ok (tools, spec, exec, dir, text, aux)

let run_user (tools : T.tools) ~dir file =
  let status, out, err = T.run [ "timeout"; "10"; tools.qemu_user; file ] in
  write (Filename.concat dir "qemu.out") (out ^ err);
  { status; file; dir }

(* The machine and loading route per architecture (design §7). *)
let system_command (tools : T.tools) (arch : Target.arch) file =
  let qemu = Option.value tools.qemu_system ~default:"qemu-system" in
  match arch with
  | Riscv32 | Riscv64 ->
      [
        qemu;
        "-M";
        "virt";
        "-smp";
        "1";
        "-m";
        "128M";
        "-bios";
        "none";
        "-nographic";
        "-monitor";
        "none";
        "-serial";
        "none";
        "-device";
        "loader,file=" ^ file ^ ",cpu-num=0";
      ]
  | _ -> Check.failf "no system-mode command for this architecture yet"

let run_system (tools : T.tools) arch ~dir file =
  let status, out, err = T.run ("timeout" :: "20" :: system_command tools arch file) in
  write (Filename.concat dir "qemu.out") (out ^ err);
  { status; file; dir }
