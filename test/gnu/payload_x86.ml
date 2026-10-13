(* The payload for x86-32 and x86-64 (AT&T syntax). The code of the check in progress is kept in
   %esi (32-bit) or %ebx (64-bit); a failed check exits with it. *)

open Payload

let make32 : (module Payload.S) =
  (module struct
    let arch = Elf.Target.X86_32

    let source (s : Spec.t) =
      let system = s.kind = `System in
      let check (code, addr, marker) =
        [ Printf.sprintf "\tmov $%d,%%esi" code; Printf.sprintf "\tmov %s,%%eax" (hex64 addr) ]
        @
        match marker with
        | Some m -> [ Printf.sprintf "\tcmp $%s,%%eax" (hex32 m); "\tjne .Lfail" ]
        | None -> [ "\ttest %eax,%eax"; "\tjnz .Lfail" ]
      in
      (* System mode: a Multiboot loader enters in 32-bit protected mode with paging off, flat
         segments, no stack and no IDT. The stack is set first (call/pop need it, which makes the
         expected address text+10: a 5-byte mov and a 5-byte call), then the trap handler is put
         at a fixed offset so the 32 exception gates can name it as an absolute constant. *)
      let entry =
        if system then
          [
            Printf.sprintf "\tmov $%s,%%esp" (hex64 (Int64.add s.stack s.stack_size));
            "\tcall 1f";
            "1:\tpop %eax";
            "\tmov $10,%esi";
            Printf.sprintf "\tcmp $%s,%%eax" (hex64 (Int64.add s.text 10L));
            "\tjne .Lfail";
            "\tjmp 4f";
            Printf.sprintf "\t.org %s" (hex64 Spec.trap_offset);
            ".Ltrap:";
            "\tmov $0x7f,%esi";
            "\tjmp .Lfail";
            "4:";
            (* Gate: (selector << 16 | offset low), (offset high | present interrupt gate). *)
            "\txor %edx,%edx";
            "\tmov %cs,%dx";
            "\tshl $16,%edx";
            Printf.sprintf "\tmov $%s,%%ebx" (hex64 (Int64.add s.text Spec.trap_offset));
            "\tmovzwl %bx,%eax";
            "\tor %edx,%eax";
            "\tmov %ebx,%ebp";
            "\tand $0xffff0000,%ebp";
            "\tor $0x8e00,%ebp";
            Printf.sprintf "\tmov $%s,%%edi" (hex64 (Option.get (Spec.idt s)));
            "\tmov $32,%ecx";
            "2:\tmov %eax,(%edi)";
            "\tmov %ebp,4(%edi)";
            "\tadd $8,%edi";
            "\tdec %ecx";
            "\tjnz 2b";
            "\tsub $8,%esp";
            "\tmovw $255,(%esp)";
            Printf.sprintf "\tmovl $%s,2(%%esp)" (hex64 (Option.get (Spec.idt s)));
            "\tlidt (%esp)";
            "\tadd $8,%esp";
          ]
          @ if s.control = `Illegal_instruction then [ "\tud2" ] else []
        else
          [
            "\tcall 1f";
            "1:\tpop %eax";
            "\tmov $10,%esi";
            Printf.sprintf "\tcmp $%s,%%eax" (hex64 (Int64.add s.text 5L));
            "\tjne .Lfail";
          ]
      in
      let finish =
        if system then
          (* isa-debug-exit at port 0xf4: writing v makes QEMU exit with status (v << 1) | 1. *)
          [
            "\tmov $0xf4,%dx";
            "\tmov $21,%eax";
            "\tout %eax,%dx";
            "5:\thlt";
            "\tjmp 5b";
            ".Lfail:";
            "\tmov $0xf4,%dx";
            "\tmov %esi,%eax";
            "\tout %eax,%dx";
            "6:\thlt";
            "\tjmp 6b";
          ]
        else
          [
            "\tmov $42,%ebx";
            "\tmov $1,%eax";
            "\tint $0x80";
            ".Lfail:";
            "\tmov %esi,%ebx";
            "\tmov $1,%eax";
            "\tint $0x80";
          ]
      in
      String.concat "\n"
        ([ "\t.section .text.main,\"ax\""; "\t.globl _start"; "_start:" ]
        @ entry
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
          ]
        @ finish
        @ [
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
