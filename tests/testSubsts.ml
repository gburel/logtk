
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

open Logtk
open OUnit

module T = FOTerm
module S = Substs.FO

let a = T.mk_const (Symbol.mk_const "a")
let b = T.mk_const (Symbol.mk_const "b")
let x = T.mk_var ~ty:Type.i 0
let y = T.mk_var ~ty:Type.i 1
let f x y = T.mk_node (Symbol.mk_const "f") [x; y]
let g x = T.mk_node (Symbol.mk_const "g") [x]
let h x y z = T.mk_node (Symbol.mk_const "h") [x;y;z]

let test_rename () =
  let t1 = f x (g y) in
  let t2 = f x (g a) in
  let t3 = g (g x) in
  let subst = FOUnif.unification t1 1 t2 0 in
  let renaming = S.Renaming.create 5 in
  let t1' = S.apply ~renaming subst t1 1 in
  let t2' = S.apply ~renaming subst t2 0 in
  let t3' = h (S.apply ~renaming subst y 1) t1' (S.apply ~renaming subst t3 0) in
  assert_bool "must be equal" (T.eq t1' t2');
  let t3'' = h a (f x (g a)) (g (g x)) in
  assert_equal ~cmp:FOUnif.are_variant ~printer:T.to_string t3'' t3';
  ()

let test_unify () =
  let x = T.mk_var ~ty:Type.(app "list" [var 0]) 0 in
  let y = T.mk_var ~ty:Type.(app "list" [int]) 1 in
  let t1 = f x (g y) in
  let t2 = f a (g x) in
  let signature = TypeInference.FO.Quick.(signature [WellTyped t1; WellTyped t2]) in
  let tyctx = TypeInference.Ctx.of_signature signature in
  let ty1 = TypeInference.FO.infer tyctx t1 0 in
  let ty2 = TypeInference.FO.infer tyctx t2 0 in
  let subst = TypeUnif.unify_fo ty1 0 ty2 1 in
  let subst = FOUnif.unification ~subst t1 0 t2 1 in
  let renaming = S.Renaming.create 5 in
  let t1' = S.apply subst ~renaming t1 0 in
  let t2' = S.apply subst ~renaming t2 0 in
  T.print_var_types := true;
  Util.printf "t1: %a, t2: %a, subst: %a\n" T.pp t1 T.pp t2 S.pp subst;
  assert_equal ~cmp:T.eq ~printer:T.to_string t1' t2';
  ()

let suite =
  "test_substs" >:::
    [ "test_rename" >:: test_rename
    ; "test_unify" >:: test_unify
    ]
