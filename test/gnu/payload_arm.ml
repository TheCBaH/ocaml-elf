(* The payload for ARM (A32, EABI): r4 holds the code of the check in progress. Constants are built
   with movw/movt so that nothing needs a literal pool or a relocation. *)

open Payload

let make : (module Payload.S) =
  (module struct
    let arch = Elf.Target.Arm

    let load32 reg v =
      let v = Int64.logand v 0xffff_ffffL in
      [
        Printf.sprintf "\tmovw %s,#%Ld" reg (Int64.logand v 0xffffL);
        Printf.sprintf "\tmovt %s,#%Ld" reg (Int64.shift_right_logical v 16);
      ]

    let source (s : Spec.t) =
      let system = s.kind = `System in
      let i32 v = Int64.logand (Int64.of_int32 v) 0xffff_ffffL in
      let check (code, addr, marker) =
        [ Printf.sprintf "\tmov r4,#%d" code ]
        @ load32 "r1" addr @ [ "\tldr r2,[r1]" ]
        @
        match marker with
        | Some m -> load32 "r3" (i32 m) @ [ "\tcmp r2,r3"; "\tbne .Lfail" ]
        | None -> [ "\tcmp r2,#0"; "\tbne .Lfail" ]
      in
      (* System mode: the kernel is entered in SVC mode with no stack and no vectors. The stack
         pointer is set right after the first instruction (which must read the PC), and VBAR points
         to a table at text+0x400 (32-byte aligned) whose entries all go to the 0x7f report. *)
      let startup =
        if system then
          load32 "r1" (Int64.add s.stack s.stack_size)
          @ [ "\tmov sp,r1"; "\tmov r4,#10" ]
          @ load32 "r1" (Int64.add s.text 8L)
          @ [ "\tcmp r0,r1"; "\tbne .Lfail" ]
          @ load32 "r1" (Int64.add s.text 0x400L)
          @ [ "\tmcr p15,0,r1,c12,c0,0"; "\tisb" ]
          (* udf #0 *)
          @ if s.control = `Illegal_instruction then [ "\t.word 0xe7f000f0" ] else []
        else
          [ "\tmov r4,#10" ] @ load32 "r1" (Int64.add s.text 8L) @ [ "\tcmp r0,r1"; "\tbne .Lfail" ]
      in
      let exit_semihosting code_reg =
        (* SYS_EXIT_EXTENDED with the parameter block {ADP_Stopped_ApplicationExit, code}. *)
        [
          "\tmovw r2,#0x26";
          "\tmovt r2,#0x2";
          Printf.sprintf "\tmov r3,%s" code_reg;
          "\tpush {r2,r3}";
          "\tmov r1,sp";
          "\tmov r0,#0x20";
          "\tsvc 0x123456";
          "\tb .";
        ]
      in
      let finish =
        if system then
          exit_semihosting "#0" @ [ ".Lfail:" ] @ exit_semihosting "r4" @ [ ".Ltrap:" ]
          (* An exception runs in another mode whose banked sp is unset. *)
          @ load32 "sp" (Int64.add s.stack s.stack_size)
          @ [ "\tmov r4,#0x7f"; "\tb .Lfail"; "\t.org 0x400" ]
          @ List.init 8 (fun _ -> "\tb .Ltrap")
        else
          [
            "\tmov r0,#42";
            "\tmov r7,#1";
            "\tsvc #0";
            ".Lfail:";
            "\tmov r0,r4";
            "\tmov r7,#1";
            "\tsvc #0";
          ]
      in
      String.concat "\n"
        ([ "\t.arm"; "\t.section .text.main,\"ax\""; "\t.globl _start"; "_start:"; "\tmov r0,pc" ]
        @ startup
        @ List.concat_map check (word_checks s)
        @ [ "\tmov r4,#17" ]
        @ load32 "r1" (Int64.add s.bss 8L)
        @ load32 "r3" (i32 s.markers.store)
        @ [ "\tstr r3,[r1]"; "\tldr r2,[r1]"; "\tcmp r2,r3"; "\tbne .Lfail"; "\tmov r4,#18" ]
        @ load32 "r3" s.aux @ [ "\tblx r3" ]
        @ load32 "r3" (i32 s.markers.aux)
        @ [ "\tcmp r0,r3"; "\tbne .Lfail" ] @ finish
        @ [ "\t.arm"; "\t.section .text.aux,\"ax\""; "\t.globl aux"; "aux:" ]
        @ load32 "r0" (i32 s.markers.aux)
        @ [ "\tbx lr"; "" ])
  end)
