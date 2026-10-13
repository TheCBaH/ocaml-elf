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
      let i32 v = Int64.logand (Int64.of_int32 v) 0xffff_ffffL in
      let check (code, addr, marker) =
        [ Printf.sprintf "\tmov w19,#%d" code ]
        @ load64 "x1" addr @ [ "\tldr w2,[x1]" ]
        @
        match marker with
        | Some m -> load32 "w3" (i32 m) @ [ "\tcmp w2,w3"; "\tb.ne .Lfail" ]
        | None -> [ "\tcbnz w2,.Lfail" ]
      in
      String.concat "\n"
        ([
           "\t.section .text.main,\"ax\"";
           "\t.globl _start";
           "_start:";
           ".Lstart:";
           "\tadr x0,.Lstart";
           "\tmov w19,#10";
         ]
        @ load64 "x1" s.text
        @ [ "\tcmp x0,x1"; "\tb.ne .Lfail" ]
        @ List.concat_map check (word_checks s)
        @ [ "\tmov w19,#17" ]
        @ load64 "x1" (Int64.add s.bss 8L)
        @ load32 "w3" (i32 s.markers.store)
        @ [ "\tstr w3,[x1]"; "\tldr w2,[x1]"; "\tcmp w2,w3"; "\tb.ne .Lfail"; "\tmov w19,#18" ]
        @ load64 "x3" s.aux @ [ "\tblr x3" ]
        @ load32 "w3" (i32 s.markers.aux)
        @ [
            "\tcmp w0,w3";
            "\tb.ne .Lfail";
            "\tmov x0,#42";
            "\tmov x8,#93";
            "\tsvc #0";
            ".Lfail:";
            "\tmov w0,w19";
            "\tmov x8,#93";
            "\tsvc #0";
            "\t.section .text.aux,\"ax\"";
            "\t.globl aux";
            "aux:";
          ]
        @ load32 "w0" (i32 s.markers.aux)
        @ [ "\tret"; "" ])
  end)
