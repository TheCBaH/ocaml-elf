type t = int64

let compare = Int64.unsigned_compare
let lt a b = compare a b < 0
let le a b = compare a b <= 0
let max a b = if lt a b then b else a

let add a b =
  let s = Int64.add a b in
  if lt s a then None else Some s

let sub a b = if lt a b then None else Some (Int64.sub a b)

let mul a b =
  if a = 0L || b = 0L then Some 0L
  else if lt (Int64.unsigned_div (-1L) b) a then None
  else Some (Int64.mul a b)

let fits_bits n v = n >= 64 || Int64.shift_right_logical v n = 0L
let is_pow2 v = v <> 0L && Int64.logand v (Int64.pred v) = 0L
let mask a = Int64.lognot (Int64.pred a)
let align_up v a = Option.map (fun s -> Int64.logand s (mask a)) (add v (Int64.pred a))
let align_down v a = Int64.logand v (mask a)
let is_aligned v a = Int64.logand v (Int64.pred a) = 0L
let rem = Int64.unsigned_rem
let to_int = Int64.unsigned_to_int

let of_int i =
  if i < 0 then invalid_arg "U64.of_int: negative";
  Int64.of_int i

let pp ppf v = Format.fprintf ppf "0x%Lx" v
