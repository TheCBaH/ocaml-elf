[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

(* The payload for AArch64: w19 holds the code of the check in progress. Constants are built with
   movz/movk, so nothing needs a literal pool or a relocation. *)

open Payload

let make : (module Payload.S) =
  (module struct
    let arch = Elf.Target.Aarch64

    (* A 64-bit constant in four 16-bit pieces. *)
    let load64 reg v =
      [
        Printf.sprintf "\tmovz %s,#%Ld" reg (Int64.logand v 0xffffL);
        Printf.sprintf "\tmovk %s,#%Ld,lsl #16" reg
          (Int64.logand (Int64.shift_right_logical v 16) 0xffffL);
        Printf.sprintf "\tmovk %s,#%Ld,lsl #32" reg
          (Int64.logand (Int64.shift_right_logical v 32) 0xffffL);
        Printf.sprintf "\tmovk %s,#%Ld,lsl #48" reg (Int64.shift_right_logical v 48);
      ]

    let load32 reg v =
      [
        Printf.sprintf "\tmovz %s,#%Ld" reg (Int64.logand v 0xffffL);
        Printf.sprintf "\tmovk %s,#%Ld,lsl #16" reg
          (Int64.shift_right_logical (Int64.logand v 0xffff_ffffL) 16);
      ]

    let source (s : Spec.t) =
      let system = s.kind = `System in
      let i32 v = Int64.logand (Int64.of_int32 v) 0xffff_ffffL in
      let check (code, addr, marker) =
        [ Printf.sprintf "\tmov w19,#%d" code ]
        @ load64 "x1" addr @ [ "\tldr w2,[x1]" ]
        @
        match marker with
        | Some m -> load32 "w3" (i32 m) @ [ "\tcmp w2,w3"; "\tb.ne .Lfail" ]
        | None -> [ "\tcbnz w2,.Lfail" ]
      in
      (* System mode: the kernel is entered at EL1 with no stack and no vectors. The stack pointer
         is set right after the first instruction (which must read the entry address), and a
         vector table at text+0x800 (2 KiB aligned) sends every exception to the 0x7f report. *)
      let startup =
        if system then
          load64 "x1" (Int64.add s.stack s.stack_size)
          @ [ "\tmov sp,x1"; "\tmov w19,#10" ]
          @ load64 "x1" s.text
          @ [ "\tcmp x0,x1"; "\tb.ne .Lfail" ]
          @ load64 "x1" (Int64.add s.text 0x800L)
          @ [ "\tmsr vbar_el1,x1"; "\tisb" ]
          @ if s.control = `Illegal_instruction then [ "\t.word 0" ] else []
        else [ "\tmov w19,#10" ] @ load64 "x1" s.text @ [ "\tcmp x0,x1"; "\tb.ne .Lfail" ]
      in
      let exit_semihosting code_reg =
        (* SYS_EXIT with the extended parameter block {ADP_Stopped_ApplicationExit, code}. *)
        [
          "\tmovz x2,#0x26";
          "\tmovk x2,#0x2,lsl #16";
          Printf.sprintf "\tmov w3,%s" code_reg;
          "\tstp x2,x3,[sp,#-16]!";
          "\tmov x1,sp";
          "\tmov x0,#0x18";
          "\thlt #0xf000";
          "\tb .";
        ]
      in
      let finish =
        if system then
          exit_semihosting "wzr" @ [ ".Lfail:" ] @ exit_semihosting "w19"
          @ [ ".Ltrap:"; "\tmov w19,#0x7f"; "\tb .Lfail"; "\t.org 0x800" ]
          @ List.concat (List.init 16 (fun _ -> [ "\t.balign 0x80"; "\tb .Ltrap" ]))
        else
          [
            "\tmov x0,#42";
            "\tmov x8,#93";
            "\tsvc #0";
            ".Lfail:";
            "\tmov w0,w19";
            "\tmov x8,#93";
            "\tsvc #0";
          ]
      in
      String.concat "\n"
        ([
           "\t.section .text.main,\"ax\"";
           "\t.globl _start";
           "_start:";
           ".Lstart:";
           "\tadr x0,.Lstart";
         ]
        @ startup
        @ List.concat_map check (word_checks s)
        @ [ "\tmov w19,#17" ]
        @ load64 "x1" (Int64.add s.bss 8L)
        @ load32 "w3" (i32 s.markers.store)
        @ [ "\tstr w3,[x1]"; "\tldr w2,[x1]"; "\tcmp w2,w3"; "\tb.ne .Lfail"; "\tmov w19,#18" ]
        @ load64 "x3" s.aux @ [ "\tblr x3" ]
        @ load32 "w3" (i32 s.markers.aux)
        @ [ "\tcmp w0,w3"; "\tb.ne .Lfail" ]
        @ finish
        @ [ "\t.section .text.aux,\"ax\""; "\t.globl aux"; "aux:" ]
        @ load32 "w0" (i32 s.markers.aux)
        @ [ "\tret"; "" ])
  end)
