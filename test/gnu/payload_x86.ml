(* The payload for x86-32 and x86-64 (AT&T syntax). The code of the check in progress is kept in
   %esi (32-bit) or %ebx (64-bit); a failed check exits with it. *)

open Payload

let make32 : (module Payload.S) =
  (module struct
    let arch = Elf.Target.X86_32

    let source (s : Spec.t) =
      let check (code, addr, marker) =
        [ Printf.sprintf "\tmov $%d,%%esi" code; Printf.sprintf "\tmov %s,%%eax" (hex64 addr) ]
        @
        match marker with
        | Some m -> [ Printf.sprintf "\tcmp $%s,%%eax" (hex32 m); "\tjne .Lfail" ]
        | None -> [ "\ttest %eax,%eax"; "\tjnz .Lfail" ]
      in
      String.concat "\n"
        ([
           "\t.section .text.main,\"ax\"";
           "\t.globl _start";
           "_start:";
           "\tcall 1f";
           "1:\tpop %eax";
           "\tmov $10,%esi";
           Printf.sprintf "\tcmp $%s,%%eax" (hex64 (Int64.add s.text 5L));
           "\tjne .Lfail";
         ]
        @ List.concat_map check (word_checks s)
        @ [
            "\tmov $17,%esi";
            Printf.sprintf "\tmov $%s,%%eax" (hex32 s.markers.store);
            Printf.sprintf "\tmov %%eax,%s" (hex64 (Int64.add s.bss 8L));
            Printf.sprintf "\tmov %s,%%ecx" (hex64 (Int64.add s.bss 8L));
            "\tcmp %eax,%ecx";
            "\tjne .Lfail";
            "\tmov $18,%esi";
            Printf.sprintf "\tmov $%s,%%ecx" (hex64 s.aux);
            "\tcall *%ecx";
            Printf.sprintf "\tcmp $%s,%%eax" (hex32 s.markers.aux);
            "\tjne .Lfail";
            "\tmov $42,%ebx";
            "\tmov $1,%eax";
            "\tint $0x80";
            ".Lfail:";
            "\tmov %esi,%ebx";
            "\tmov $1,%eax";
            "\tint $0x80";
            "\t.section .text.aux,\"ax\"";
            "\t.globl aux";
            "aux:";
            Printf.sprintf "\tmov $%s,%%eax" (hex32 s.markers.aux);
            "\tret";
            "";
          ])
  end)

let make64 : (module Payload.S) =
  (module struct
    let arch = Elf.Target.X86_64

    let source (s : Spec.t) =
      let check (code, addr, marker) =
        [
          Printf.sprintf "\tmov $%d,%%ebx" code;
          Printf.sprintf "\tmovabs $%s,%%rax" (hex64 addr);
          "\tmov (%rax),%ecx";
        ]
        @
        match marker with
        | Some m -> [ Printf.sprintf "\tcmp $%s,%%ecx" (hex32 m); "\tjne .Lfail" ]
        | None -> [ "\ttest %ecx,%ecx"; "\tjnz .Lfail" ]
      in
      String.concat "\n"
        ([
           "\t.section .text.main,\"ax\"";
           "\t.globl _start";
           "_start:";
           ".Lstart:";
           "\tlea .Lstart(%rip),%rax";
           "\tmov $10,%ebx";
           Printf.sprintf "\tmovabs $%s,%%rcx" (hex64 s.text);
           "\tcmp %rcx,%rax";
           "\tjne .Lfail";
         ]
        @ List.concat_map check (word_checks s)
        @ [
            "\tmov $17,%ebx";
            Printf.sprintf "\tmovabs $%s,%%rax" (hex64 (Int64.add s.bss 8L));
            Printf.sprintf "\tmov $%s,%%ecx" (hex32 s.markers.store);
            "\tmov %ecx,(%rax)";
            "\tmov (%rax),%edx";
            "\tcmp %ecx,%edx";
            "\tjne .Lfail";
            "\tmov $18,%ebx";
            Printf.sprintf "\tmovabs $%s,%%rcx" (hex64 s.aux);
            "\tcall *%rcx";
            Printf.sprintf "\tcmp $%s,%%eax" (hex32 s.markers.aux);
            "\tjne .Lfail";
            "\tmov $42,%edi";
            "\tmov $60,%eax";
            "\tsyscall";
            ".Lfail:";
            "\tmov %ebx,%edi";
            "\tmov $60,%eax";
            "\tsyscall";
            "\t.section .text.aux,\"ax\"";
            "\t.globl aux";
            "aux:";
            Printf.sprintf "\tmov $%s,%%eax" (hex32 s.markers.aux);
            "\tret";
            "";
          ])
  end)
