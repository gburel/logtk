
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

(** {1 Meta-Prover} *)

open Logtk
open Logtk_parsers

module P = Plugin
module R = Reasoner
module PT = PrologTerm

type t = {
  reasoner : Reasoner.t;
  plugins : Plugin.set;
}

type clause = Reasoner.clause

let empty = {
  reasoner = R.empty;
  plugins = P.Base.set;
}

let reasoner p = p.reasoner

let plugins p = p.plugins

let signature p = P.signature_of_set p.plugins

let add p clause =
  let r', consequences = R.add p.reasoner clause in
  {p with reasoner=r'; }, consequences

let add_fact p fact =
  add p (R.Clause.rule fact [])

let add_fo_clause p clause =
  let fact = Plugin.holds#to_fact clause in
  add_fact p fact

module Seq = struct
  let to_seq p = R.Seq.to_seq p.reasoner
  let of_seq p seq =
    let r', consequences = R.Seq.of_seq p.reasoner seq in
    {p with reasoner=r'; }, consequences
end

(** {6 IO} *)

(* convert prolog term's literals into their multiset version *)
let convert_lits t =
  let a = object
    inherit PT.id_visitor
    method app ?loc f l =
      match PT.view f with
      | PT.Const (Symbol.Conn
        (Symbol.Eq | Symbol.Neq | Symbol.Equiv | Symbol.Or | Symbol.And) as s) ->
          (* transform some connective into multisets *)
          PT.app ?loc (PT.const s) [PT.list_ l]
      | _ -> PT.app ?loc f l
  end in
  a#visit t

(* convert an AST to a clause, if needed. In any case update the
 * context *)
let __clause_of_ast ~ctx = function
  | Ast_ho.Clause (head, body) ->
      (* first, conversion *)
      let head = convert_lits head in
      let body = List.map convert_lits body in
      (* expected type *)
      let ret = Reasoner.property_ty in
      (* infer types for head, body, and force all types to be [ret] *)
      let ty_head, head' = TypeInference.HO.infer ctx head in
      TypeInference.Ctx.constrain_type_type ctx ty_head ret;
      let body' = List.map
        (fun t ->
          let ty, t' = TypeInference.HO.infer ctx t in
          TypeInference.Ctx.constrain_type_type ctx ty ret;
          t')
        body
      in
      let body' = TypeInference.Closure.seq body' in
      (* generalize *)
      TypeInference.Ctx.generalize ctx;
      let head' = head' ctx in
      let body' = body' ctx in
      TypeInference.Ctx.exit_scope ctx;
      Some (Reasoner.Clause.rule head' body')
  | Ast_ho.Type (s, ty) ->
      (* declare the type *)
      begin match TypeInference.Ctx.ty_of_prolog ctx ty with
      | None -> None
      | Some ty ->
        TypeInference.Ctx.declare ctx (Symbol.of_string s) ty;
        None
      end

let of_ho_ast p decls =
  try
    let ctx = TypeInference.Ctx.create Encoding.signature in
    let clauses = Sequence.fmap (__clause_of_ast ~ctx) decls in
    let p', consequences = Seq.of_seq p clauses in
    Monad.Err.Ok (p', consequences)
  with Type.Error msg ->
    Monad.Err.fail msg

let parse_file p filename =
  try
    let ic = open_in filename in
    begin try
      let decls = Parse_ho.parse_decls Lex_ho.token (Lexing.from_channel ic) in
      let res = of_ho_ast p (Sequence.of_list decls) in
      close_in ic;
      res
    with
    | Parse_ho.Error ->
      close_in ic;
      Monad.Err.fail "parse error"
    | Lex_ho.Error msg ->
      close_in ic;
      Monad.Err.fail ("lexing error: " ^ msg)
    end
  with Sys_error msg ->
    let msg = Printf.sprintf "could not open file %s: %s" filename msg in
    Monad.Err.fail msg