[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

(* Prints an MD5 digest of every executable built from a fixed set of specs. Native, bytecode and
   js_of_ocaml runs must print the same lines (checked by the dune rules next to this file). *)

open Elf

let digest name spec =
  match Exec.build spec with
  | Ok bytes ->
      Printf.printf "%s %d %s\n" name (String.length bytes) (Digest.to_hex (Digest.string bytes))
  | Error e ->
      Printf.printf "%s error: %s\n" name (Format.asprintf "%a" (Err.Error.pp_kind Exec.pp_error) e)

let targets =
  [
    ("rv32", Target.riscv Riscv.rv32imafd_ilp32d);
    ("rv32-soft", Target.riscv Riscv.rv32im_ilp32);
    ("rv64", Target.riscv Riscv.rv64imafd_lp64d);
    ("x86-32", Target.x86_32);
    ("x86-64", Target.x86_64);
    ("arm", Target.arm { Arm.hard_float with attributes = Some Arm.armv7a_attributes });
    ("aarch64", Target.aarch64 ());
  ]

(* Many tiny sections: extended section numbering. *)
let many_sections n =
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
  {
    Exec.target = Target.x86_32;
    entry = 0x40_1000L;
    headers = Exec.Mapped { vaddr = 0x40_0000L; paddr = None };
    gnu_stack = None;
    section_headers = true;
    segments = [ { perms = rx; paddr = None; sections } ];
    symbols = [];
  }

let () =
  Err.Config.set Err.Config.deterministic;
  List.iter
    (fun (name, target) ->
      List.iter
        (fun (variant, base, sections) ->
          let base =
            if Target.(target.elf_class) = Types.Elf64 && base > 0x7fff_ffffL then 0x1_2000_0000L
            else base
          in
          digest
            (Printf.sprintf "%s/%s" name variant)
            (Elf_test_support.Sample.spec ~base ~sections target))
        [
          ("sections", 0x40_0000L, true); ("bare", 0x40_0000L, false); ("high", 0x9000_0000L, true);
        ])
    targets;
  digest "many-sections" (many_sections 0xff10)
