(* The payload for RV32 and RV64. [s1] holds the code of the check in progress; a failed check
   exits with it. *)

let make (arch : Elf.Target.arch) : (module Payload.S) =
  (module struct
    let arch = arch

    let source (s : Spec.t) =
      let a v = Printf.sprintf "0x%Lx" v in
      let m v = Printf.sprintf "0x%lx" v in
      let init = Int64.of_int s.data_init in
      let system = s.kind = `System in
      (* System mode: the core starts in M-mode with no firmware and no stack, so startup sets
         [sp] and [mtvec] after the first check (which must run at the entry point). A trap
         reports 0x7f. *)
      let prologue =
        if system then
          [
            (* The trap handler sits at a fixed offset, so its address is an absolute constant
               and needs no relocation. *)
            "\tj 4f";
            "\t.org 0x40";
            ".Ltrap:";
            "\tli s1,0x7f";
            "\tj .Lfail";
            "4:";
            Printf.sprintf "\tli sp,%s" (a (Int64.add s.stack s.stack_size));
            Printf.sprintf "\tli t0,%s" (a (Int64.add s.text 0x40L));
            "\tcsrw mtvec,t0";
          ]
          @ if s.control = `Illegal_instruction then [ "\t.word 0" ] else []
        else []
      in
      let finish =
        if system then
          [
            (* SiFive test device: 0x5555 passes; (code << 16) | 0x3333 fails with that code. *)
            "\tli t0,0x100000";
            "\tli t1,0x5555";
            "\tsw t1,0(t0)";
            "1:\tj 1b";
            ".Lfail:";
            "\tslli t1,s1,16";
            "\tli t2,0x3333";
            "\tor t1,t1,t2";
            "\tli t0,0x100000";
            "\tsw t1,0(t0)";
            "2:\tj 2b";
          ]
        else
          [
            "\tli a0,42"; "\tli a7,93"; "\tecall"; ".Lfail:"; "\tmv a0,s1"; "\tli a7,93"; "\tecall";
          ]
      in
      let lines =
        [
          "\t.option norelax";
          "\t.section .text.main,\"ax\"";
          "\t.globl _start";
          "_start:";
          "\tauipc t0,0";
          "\tli s1,10";
          Printf.sprintf "\tli t1,%s" (a s.text);
          "\tbne t0,t1,.Lfail";
        ]
        @ prologue
        @ List.concat_map
            (fun (code, addr, marker) ->
              [
                Printf.sprintf "\tli s1,%d" code;
                Printf.sprintf "\tli t0,%s" (a addr);
                "\tlw t1,0(t0)";
                (match marker with
                | Some v -> Printf.sprintf "\tli t2,%s\n\tbne t1,t2,.Lfail" (m v)
                | None -> "\tbnez t1,.Lfail");
              ])
            [
              (11, s.rodata, Some s.markers.rodata);
              (12, s.data, Some s.markers.data);
              (13, Int64.add s.data init, None);
              (14, Int64.sub (Int64.add (Int64.add s.data init) s.data_zero) 4L, None);
              (15, s.bss, None);
              (16, Int64.sub (Int64.add s.bss s.bss_size) 4L, None);
            ]
        @ [
            "\tli s1,17";
            Printf.sprintf "\tli t0,%s" (a (Int64.add s.bss 8L));
            Printf.sprintf "\tli t2,%s" (m s.markers.store);
            "\tsw t2,0(t0)";
            "\tlw t1,0(t0)";
            "\tbne t1,t2,.Lfail";
            "\tli s1,18";
            Printf.sprintf "\tli t0,%s" (a s.aux);
            "\tjalr ra,0(t0)";
            Printf.sprintf "\tli t2,%s" (m s.markers.aux);
            "\tbne a0,t2,.Lfail";
          ]
        @ finish
        @ [
            "\t.section .text.aux,\"ax\"";
            "\t.globl aux";
            "aux:";
            Printf.sprintf "\tli a0,%s" (m s.markers.aux);
            "\tret";
            "";
          ]
      in
      String.concat "\n" lines
  end)
