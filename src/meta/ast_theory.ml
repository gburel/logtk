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

(** {1 Theory AST} *)

open Logtk

module PT = PrologTerm

exception ParseError of ParseLocation.t

type statement =
  | Lemma of string * string list * premise list
  | LemmaInline of BF.t * premise list
  | Axiom of string * string list * BF.t
  | Theory of string * string list * premise list
  | Clause of clause
  | Include of string
  (** Parse statement *)
and premise =
  | IfPattern of BF.t
  | IfAxiom of string * string list
  | IfTheory of string * string list
and clause = raw_lit * raw_lit list
and raw_lit = string * string list

(** Print a statement *)
let pp buf statement =
  let pp_datalog buf (s, args) = match args with
  | [] -> Buffer.add_string buf s
  | _ ->
    Printf.bprintf buf "%s(%a)" s (Util.pp_list Buffer.add_string) args
  in
  let pp_premise buf premise = match premise with
  | IfPattern t -> BF.pp buf t
  | IfAxiom (s, args) -> Printf.bprintf buf "axiom %a" pp_datalog (s, args)
  | IfTheory (s, args) -> Printf.bprintf buf "theory %a" pp_datalog (s, args)
  in
  let pp_premises buf premises =
    Util.pp_list ~sep:" and " pp_premise buf premises
  and pp_lit buf lit = match lit with
  | s, [] -> Buffer.add_string buf s
  | s, args ->
    Printf.bprintf buf "%s(%a)" s (Util.pp_list Buffer.add_string) args
  in
  match statement with
  | Lemma (s, args, premises) ->
    Printf.bprintf buf "lemma %a if %a."
      pp_datalog (s,args) pp_premises premises
  | LemmaInline (f, premises) ->
    Printf.bprintf buf "lemma axiom %a if %a."
      BF.pp f pp_premises premises
  | Axiom (s, args, f) ->
    Printf.bprintf buf "%a is axiom %a." pp_datalog (s, args) BF.pp f
  | Theory (s, args, premises) ->
    Printf.bprintf buf "theory %a is %a." pp_datalog (s, args)
      pp_premises premises
  | Clause (head, []) -> Printf.bprintf buf "%a." pp_lit head
  | Clause (head, body) ->
    Printf.bprintf buf "%a :- %a." pp_lit head (Util.pp_list pp_lit) body
  | Include s ->
    Printf.bprintf buf "include %s." s

(** Print a list of statements, separated by \n *)
let pp_statements buf statements =
  let pp_stmt buf st = Printf.bprintf buf "%a\n" pp st in
  Util.pp_list pp_stmt buf statements

(** Generalize the variables occurring in the statement *)
let generalize_statement stmt =
  let generalize_premise p = match p with
  | IfPattern f -> IfPattern (BF.generalize_vars f)
  | IfAxiom _
  | IfTheory _ -> p
  in
  let generalize_premises = List.map generalize_premise in
  match stmt with
  | Lemma (n,l, premises) -> Lemma (n,l, generalize_premises premises)
  | LemmaInline(f, premises) -> LemmaInline(BF.generalize_vars f, generalize_premises premises)
  | Axiom (n,l, f) -> Axiom (n,l, BF.generalize_vars f)
  | Theory (n,l, premises) -> Theory (n,l, generalize_premises premises)
  | Clause _
  | Include _ -> stmt
