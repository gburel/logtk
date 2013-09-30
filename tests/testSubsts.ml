
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

module T = Term
module S = Substs
module TT = TestTerm

let test_rename () =
  let t1 = TT.(f x (g y)) in
  let t2 = TT.(f x (g a)) in
  let t3 = TT.(g (g x)) in
  let subst = Unif.unification t1 1 t2 0 in
  let renaming = Substs.Renaming.create 5 in
  let t1' = S.apply ~renaming subst t1 1 in
  let t2' = S.apply ~renaming subst t2 0 in
  let t3' = TT.(h (S.apply ~renaming subst y 1) t1' (S.apply ~renaming subst t3 0)) in
  assert_bool "must be equal" (T.eq t1' t2');
  let t3'' = TT.pterm "h(a, f(X, g(a)), g(g(X)))" in
  assert_equal ~cmp:Unif.are_variant ~printer:T.to_string t3'' t3';
  ()

let suite =
  "test_substs" >:::
    [ "test_rename" >:: test_rename
    ]