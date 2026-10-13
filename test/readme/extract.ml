[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

(* Prints the first ```ocaml block of a Markdown file, then [ran], which the test refers to so the
   example is linked, and therefore run, before the test body. *)

let () =
  let ic = open_in Sys.argv.(1) in
  let rec skip () =
    match input_line ic with
    | "```ocaml" -> ()
    | _ -> skip ()
    | exception End_of_file ->
        prerr_endline "no ocaml block";
        exit 1
  in
  skip ();
  let rec copy () =
    match input_line ic with
    | "```" -> print_endline "\nlet ran = true"
    | line ->
        print_endline line;
        copy ()
    | exception End_of_file ->
        prerr_endline "unterminated ocaml block";
        exit 1
  in
  copy ()
