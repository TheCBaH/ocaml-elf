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
      let i32 v = Int64.logand (Int64.of_int32 v) 0xffff_ffffL in
      let check (code, addr, marker) =
        [ Printf.sprintf "\tmov r4,#%d" code ]
        @ load32 "r1" addr @ [ "\tldr r2,[r1]" ]
        @
        match marker with
        | Some m -> load32 "r3" (i32 m) @ [ "\tcmp r2,r3"; "\tbne .Lfail" ]
        | None -> [ "\tcmp r2,#0"; "\tbne .Lfail" ]
      in
      String.concat "\n"
        ([
           "\t.arm";
           "\t.section .text.main,\"ax\"";
           "\t.globl _start";
           "_start:";
           "\tmov r0,pc";
           "\tmov r4,#10";
         ]
        @ load32 "r1" (Int64.add s.text 8L)
        @ [ "\tcmp r0,r1"; "\tbne .Lfail" ]
        @ List.concat_map check (word_checks s)
        @ [ "\tmov r4,#17" ]
        @ load32 "r1" (Int64.add s.bss 8L)
        @ load32 "r3" (i32 s.markers.store)
        @ [ "\tstr r3,[r1]"; "\tldr r2,[r1]"; "\tcmp r2,r3"; "\tbne .Lfail"; "\tmov r4,#18" ]
        @ load32 "r3" s.aux @ [ "\tblx r3" ]
        @ load32 "r3" (i32 s.markers.aux)
        @ [
            "\tcmp r0,r3";
            "\tbne .Lfail";
            "\tmov r0,#42";
            "\tmov r7,#1";
            "\tsvc #0";
            ".Lfail:";
            "\tmov r0,r4";
            "\tmov r7,#1";
            "\tsvc #0";
            "\t.arm";
            "\t.section .text.aux,\"ax\"";
            "\t.globl aux";
            "aux:";
          ]
        @ load32 "r0" (i32 s.markers.aux)
        @ [ "\tbx lr"; "" ])
  end)
