(** Instruction lines of [objdump -d] output, for comparing a disassembly of an object with one of
    the linked executable. *)

val instructions : vma:int64 -> string -> (string * string) list
(** [(encoding bytes, text)] per instruction. The text keeps the mnemonic and operands, without the
    trailing [# ...] comment and [<symbol>] annotation, and with a branch target rebased by
    subtracting [vma] (the address the section starts at), so that an object's section (vma 0)
    and the same code placed at [vma] give equal lists. *)
