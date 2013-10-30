
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

(** {1 Lambda-Calculus} *)

let prof_beta_reduce = Util.mk_profiler "HO.beta_reduce"
let prof_lambda_abstract = Util.mk_profiler "HO.lambda_abstract"

type term = HOTerm.t

module T = HOTerm

(* TODO: flag to check whether a term is beta-reduced *)

let beta_reduce ?(depth=0) t =
  Util.enter_prof prof_beta_reduce;
  (* recursive reduction in call by value. [env] contains the environment for
  De Bruijn indexes. *)
  let rec beta_reduce ~depth env t = match t.T.term with
  | T.Var _ -> t
  | T.BoundVar n when n < List.length env ->
    (* look for the possible binding for [n] *)
    begin match List.nth env n with
    | None -> t
    | Some t' when T.eq t t' -> t
    | Some t' -> T.db_lift ~depth depth t' (* need to lift free vars *)
    end
  | T.Const _
  | T.BoundVar _ -> t
  | T.Lambda t' ->
    let varty = T.lambda_var_ty t in
    let t'' = beta_reduce ~depth:(depth+1) (None::env) t' in
    T.mk_lambda ~varty t''
  | T.At ({T.term=T.Lambda t1}, t2::l) ->
    (* a beta-redex! Fire!! First evaluate t2, then remplace
        db0 by [t2] in [t1] *)
    let t2' = beta_reduce ~depth env t2 in
    let env' = Some t2' :: env in
    let t1' = beta_reduce ~depth env' t1 in
    (* now reduce t1 @ l, if l not empty *)
    begin match l with
      | [] -> t1'
      | _::_ -> beta_reduce ~depth env (T.mk_at t1 l)
    end
  | T.At (t, l) ->
    let t' = beta_reduce ~depth env t in
    let l' = List.map (beta_reduce ~depth env) l in
    if T.eq t t' && List.for_all2 T.eq l l'
      then t
      else beta_reduce ~depth env (T.mk_at t' l')  (* new redex? *)
  in
  let t' = beta_reduce ~depth [] t in
  Util.exit_prof prof_beta_reduce;
  t'

let rec eta_reduce t =
  match t.T.term with
  | T.Var _ | T.BoundVar _ | T.Const _ -> t
  | T.Lambda {T.term=T.At (t', [{T.term=T.BoundVar 0}])} when not (T.db_contains t' 0) ->
    eta_reduce (T.db_unlift t')  (* remove the lambda and variable *)
  | T.Lambda t' ->
    let varty = T.lambda_var_ty t in
    T.mk_lambda ~varty (eta_reduce t')
  | T.At (t, l) ->
    T.mk_at (eta_reduce t) (List.map eta_reduce l)

let lambda_abstract t sub_t =
  Util.enter_prof prof_lambda_abstract;
  (* abstract the term *)
  let t' = T.db_from_term t sub_t in
  let varty = sub_t.T.ty in
  let t' = T.mk_lambda ~varty t' in
  Util.exit_prof prof_lambda_abstract;
  t'

let lambda_abstract_list t args =
  List.fold_left lambda_abstract t args

let lambda_apply_list t args =
  let t' = T.mk_at t args in
  let t' = beta_reduce t' in
  t'
