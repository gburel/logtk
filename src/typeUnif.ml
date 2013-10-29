
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

(** {1 Unification of Types} *)

module Ty = Type
module S = Substs.Ty

let prof_unify = Util.mk_profiler "TypeUnif.unify"
let prof_variant = Util.mk_profiler "TypeUnif.variant"

type scope = Substs.scope

type error = {
  left : Type.t;
  s_left : scope;
  right : Type.t;
  s_right : scope;
  subst : Substs.Ty.t;
}

exception Error of error

let _error subst ty1 s1 ty2 s2 =
  raise (Error {
    left = ty1;
    s_left = s1;
    right = ty2;
    s_right = s2;
    subst;
  })

let pp_error buf e =
  Printf.bprintf buf "type error when unifying %a[%d] with %a[%d] in context %a"
    Ty.pp e.left e.s_left Ty.pp e.right e.s_right S.pp e.subst

let error_to_string = Util.on_buffer pp_error

(* occur-check *)
let _occur_check subst v s_v t s_t =
  let rec check t s_t = match t with
  | Ty.Var _ when s_v = s_t && Ty.eq v t -> true
  | Ty.Var _ ->
    begin try
      let t', s_t' = S.lookup subst t s_t in
      check t' s_t'
    with Not_found -> false
    end
  | Ty.App (_, l) -> List.exists (fun t' -> check t' s_t) l
  | Ty.Fun (ret, l) ->
    check ret s_t || List.exists (fun t' -> check t' s_t) l
  in
  check t s_t

(* unification *)
let rec _unify_rec subst ty1 s1 ty2 s2 =
  let ty1, s1 = S.get_var subst ty1 s1 in
  let ty2, s2 = S.get_var subst ty2 s2 in
  match ty1, ty2 with
  | _ when s1 = s2 && Ty.eq ty1 ty2 -> subst
  | Ty.Var _, _ ->
    if _occur_check subst ty1 s1 ty2 s2
      then _error subst ty1 s1 ty2 s2
      else S.bind subst ty1 s1 ty2 s2
  | _, Ty.Var _ ->
    if _occur_check subst ty2 s2 ty1 s1
      then _error subst ty2 s2 ty1 s1
      else S.bind subst ty2 s2 ty1 s1
  | Ty.App (sym1, l1), Ty.App (sym2, l2) when sym1 = sym2 && List.length l1 = List.length l2 ->
    List.fold_left2
      (fun subst ty1 ty2 -> _unify_rec subst ty1 s1 ty2 s2)
      subst
      l1 l2
  | Ty.Fun (ret1, l1), Ty.Fun (ret2, l2) when List.length l1 = List.length l2 ->
    let subst = _unify_rec subst ret1 s1 ret2 s2 in
    List.fold_left2
      (fun subst ty1 ty2 -> _unify_rec subst ty1 s1 ty2 s2)
      subst
      l1 l2
  | _ -> _error subst ty1 s1 ty2 s2

let unify ?(subst=S.create 10) ty1 s1 ty2 s2 =
  Util.enter_prof prof_unify;
  try
    let subst = _unify_rec subst ty1 s1 ty2 s2 in
    Util.exit_prof prof_unify;
    subst
  with e ->
    Util.exit_prof prof_unify;
    raise e

let unify_fo ?(subst=Substs.FO.create 11) ty1 s1 ty2 s2 =
  Substs.FO.update_ty subst
    (fun subst -> unify ~subst ty1 s1 ty2 s2)

let unify_ho ?(subst=Substs.HO.create 11) ty1 s1 ty2 s2 =
  Substs.HO.update_ty subst
    (fun subst -> unify ~subst ty1 s1 ty2 s2)

let are_unifiable ty1 ty2 =
  try
    ignore (unify ty1 0 ty2 1);
    true
  with Error _ ->
    false

let unifier ty1 ty2 =
  let subst = unify ty1 0 ty2 1 in
  let renaming = S.Renaming.create 5 in
  let ty = S.apply subst ~renaming ty1 0 in
  ty

(* alpha-equivalence check *)
let rec _variant_rec subst ty1 s1 ty2 s2 =
  let ty1, s1 = S.get_var subst ty1 s1 in
  let ty2, s2 = S.get_var subst ty2 s2 in
  match ty1, ty2 with
  | _ when s1 = s2 && Ty.eq ty1 ty2 -> subst
  | Ty.Var i1, Ty.Var i2 ->
    (* can bind variables if they do not belong to the same scope *)
    if s1 <> s2
      then S.bind subst ty1 s1 ty2 s2
      else _error subst ty1 s1 ty2 s2
  | _, Ty.Var _
  | Ty.Var _, _ -> _error subst ty2 s2 ty1 s1
  | Ty.App (sym1, l1), Ty.App (sym2, l2) when sym1 = sym2 && List.length l1 = List.length l2 ->
    List.fold_left2
      (fun subst ty1 ty2 -> _unify_rec subst ty1 s1 ty2 s2)
      subst
      l1 l2
  | Ty.Fun (ret1, l1), Ty.Fun (ret2, l2) when List.length l1 = List.length l2 ->
    let subst = _unify_rec subst ret1 s1 ret2 s2 in
    List.fold_left2
      (fun subst ty1 ty2 -> _unify_rec subst ty1 s1 ty2 s2)
      subst
      l1 l2
  | _ -> _error subst ty1 s1 ty2 s2

let variant ?(subst=S.create 10) ty1 s1 ty2 s2 =
  Util.enter_prof prof_variant;
  try
    let subst = _variant_rec subst ty1 s1 ty2 s2 in
    Util.exit_prof prof_variant;
    subst
  with e ->
    Util.exit_prof prof_variant;
    raise e

let are_variants ty1 ty2 =
  try
    ignore (variant ty1 0 ty2 1);
    true
  with Error _ ->
    false