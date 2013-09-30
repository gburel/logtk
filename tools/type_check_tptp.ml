
(*
Copyright (c) 2013, Simon Cruanes
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.  Redistributions in binary
form must reproduce the above copyright notice, this list of conditions and the
following disclaimer in the documentation and/or other materials provided with
the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*)

(** {1 TPTP Syntax and types checking} *)

open Logtk

module F = Formula

let printer = ref F.pp

let print_line () =
  Printf.printf "%s\n" (Util.str_repeat "=" 60);
  ()

let cat_input = ref false  (* print input declarations? *)
let stats = ref false
let pp_base = ref false

let options =
  [ "-debug", Arg.Int Util.set_debug, "debug level"
  ; "-cat", Arg.Set cat_input, "print input declarations"
  ; "-profile", Arg.Set Util.enable_profiling, "enable profiling"
  ; "-stats", Arg.Set stats, "statistics"
  ; "-base", Arg.Set pp_base, "print signature of base symbols"
  ; "-tstp", Arg.Unit (fun () -> printer := F.pp_tstp), "output in TSTP format"
  ]

(* check the given file *)
let check file =
  print_line ();
  Printf.printf "checking file %s...\n" file;
  try
    (* parse *)
    let decls = Util_tptp.parse_file ~recursive:true file in
    (if !cat_input
      then Sequence.iter
        (fun d -> Util.printf "%a\n" Ast_tptp.pp_declaration d) decls);
    (* type check *)
    let signature = if !pp_base
      then Util_tptp.signature decls
      else Signature.diff (Util_tptp.signature decls) Signature.base
    in
    Printf.printf "signature:\n";
    Signature.iter signature
      (fun s ty -> Util.printf "  %a : %a\n" Symbol.pp s Type.pp ty);
    Printf.printf "formulas:\n";
    Sequence.iter
      (fun f -> Util.printf "  %a\n" !printer f)
      (Util_tptp.formulas decls);
    (if !stats then begin
      Util.printf "number of symbols: %d\n" (Signature.size signature);
      Util.printf "number of input declarations: %d\n" (Sequence.length decls);
      end);
  with
  | Util_tptp.ParseError _ as e ->
    (* syntax error *)
    Printf.printf "%s\n" (Util_tptp.string_of_error e);
    exit 1
  | Type.Error msg ->
    Printf.printf "%s\n" msg;
    exit 1

let main () =
  let files = ref [] in
  let add_file f = files := f :: !files in
  Arg.parse options add_file "check_tptp [options] [file1|stdin] file2...";
  (if !files = [] then files := ["stdin"]);
  files := List.rev !files;
  List.iter check !files;
  print_line ();
  Printf.printf "success!\n";
  ()

let _ =
  main ()