
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

(** {1 Experimental Fingerprint Indexing}
This implementation of fingerprint indexing should take types into
account, and also only traverse the relevant parts of the tree.

TODO: pre-index on types? *)

module T = FOTerm
module I = Index
module S = Substs.FO

let prof_traverse = Util.mk_profiler "fastFingerprint.traverse"

type feature =
  | A (* variable *)
  | B (* under variable *)
  | N (* not a position *)
  | S of Symbol.t (* symbol application *)

type fingerprint = feature array

type fingerprint_fun = T.t -> fingerprint

(** compute a feature for a given position *)
let rec gfpf pos t = match pos, t.T.term with
  | [], T.Var _ -> A
  | [], T.BoundVar _ -> S Symbol.db_symbol
  | [], T.Node (s, _) -> S s
  | i::pos', T.Node (_, l) ->
    (try gfpf pos' (List.nth l i)  (* recurse in subterm *)
    with Failure _ -> N)  (* not a position in t *)
  | _::_, T.BoundVar _ -> N
  | _::_, T.Var _ -> B  (* under variable *)

(** compute a feature vector for some positions *)
let fp positions =
  let positions = Array.of_list positions in
  fun t ->
    Array.map (fun pos -> gfpf pos t) positions

(** {2 Fingerprint functions} *)

let fp3d = fp [[]; [1]; [1;1]]
let fp3w = fp [[]; [1]; [2]]
let fp4d = fp [[]; [1]; [1;1;]; [1;1;1]]
let fp4m = fp [[]; [1]; [2]; [1;1]]
let fp4w = fp [[]; [1]; [2]; [3]]
let fp5m = fp [[]; [1]; [2]; [3]; [1;1]]
let fp6m = fp [[]; [1]; [2]; [3]; [1;1]; [1;2]]
let fp7  = fp [[]; [1]; [2]; [1;1]; [1;2]; [2;1] ; [2;2]]
let fp7m = fp [[]; [1]; [2]; [3]; [1;1]; [4]; [1;2]]
let fp16 = fp [[]; [1]; [2]; [3]; [4]; [1;1]; [1;2]; [1;3]; [2;1];
               [2;2]; [2;3]; [3;1]; [3;2]; [3;3]; [1;1;1]; [2;1;1]]

(** {2 The index} *)

let eq_features f1 f2 = match f1, f2 with
  | N, N
  | B, B
  | A, A -> true
  | S s1, S s2 -> Symbol.eq s1 s2
  | _ -> false

let hash_feature f = match f with
  | N -> 2
  | B -> 3
  | A -> 5
  | S s -> Symbol.hash s

module PH = PersistentHashtbl.Make(struct
  type t = feature
  let equal = eq_features
  let hash = hash_feature
end)

module Make(X : Set.OrderedType) = struct
  type elt = X.t

  module Leaf = Index.MakeLeaf(X)

  type trie = {
    leaf : Leaf.t;
    sub : trie PH.t;
  }

  let empty_trie () = {
    leaf = Leaf.empty;
    sub = PH.create 7;
  }

  type t = {
    trie : trie;
    fp : fingerprint_fun;
  }

  let default_fp = fp7m

  let empty_with fp = {
    trie = empty_trie ();
    fp;
  }

  let empty () = empty_with default_fp

  let get_fingerprint idx = idx.fp

  let name = "fast_fingerprint_idx"

  let rec is_empty_trie t =
    Leaf.is_empty t.leaf &&
    try
      PH.iter t.sub (fun _ trie' -> if not (is_empty_trie trie') then raise Exit);
      true
    with Exit -> false

  let is_empty idx = is_empty_trie idx.trie

  (* goto the leaf that has the given fingerprint, and apply [k] to it.
    this may add or remove a leaf. *)
  let rec goto_leaf trie fingerprint i k =
    if i = Array.length fingerprint
      then
        let trie' = k trie in
        k trie'
      else
        let feature = fingerprint.(i) in
        let subtrie =
          try PH.find trie.sub feature
          with Not_found -> empty_trie ()
        in
        let subtrie' = goto_leaf subtrie fingerprint (i+1) k in
        if is_empty_trie subtrie'
          then {trie with sub=PH.remove trie.sub feature}
          else {trie with sub=PH.replace trie.sub feature subtrie'}
  
  let add idx t data =
    let fingerprint = idx.fp t in
    let trie = goto_leaf idx.trie fingerprint 0
      (fun trie -> {trie with leaf = Leaf.add trie.leaf t data; })
    in
    { idx with trie; }

  let remove idx t data =
    let fingerprint = idx.fp t in
    let trie = goto_leaf idx.trie fingerprint 0
      (fun trie -> {trie with leaf = Leaf.remove trie.leaf t data; })
    in
    { idx with trie; }

  let iter idx f =
    let rec iter_trie trie f =
      Leaf.iter trie.leaf f;
      PH.iter trie.sub (fun _ trie' -> iter_trie trie' f)
    in
    iter_trie idx.trie f

  let fold idx f acc =
    let rec fold_trie trie acc f =
      let acc = Leaf.fold trie.leaf acc f in
      PH.fold (fun acc _ trie' -> fold_trie trie' acc f) acc trie.sub
    in
    fold_trie idx.trie acc f

  (** number of indexed terms *)
  let size idx =
    let n = ref 0 in
    iter idx (fun _ _ -> incr n);
    !n

  (* try to follow the branch with this given feature *)
  let rec try_feature k trie acc i feature =
    try k (PH.find trie.sub feature) acc (i+1)
    with Not_found -> acc

  (* try all S branches *)
  let rec all_symbols k trie acc i =
    PH.fold
      (fun acc feat' trie' -> match feat' with
        | S _ -> k trie' acc (i+1)
        | _ -> acc)
      acc trie.sub

  let retrieve_unifiables ?(subst=S.empty ()) idx o_i t o_t acc f =
    let fingerprint = idx.fp t in
    let rec retrieve trie acc i =
      if i = Array.length fingerprint
        then Leaf.fold_unify ~subst trie.leaf o_i t o_t acc f
      else
        let feat = fingerprint.(i) in
        match feat with
        | S s ->
          let acc = try_feature retrieve trie acc i feat in
          let acc = try_feature retrieve trie acc i A in
          try_feature retrieve trie acc i B
        | A ->
          let acc = try_feature retrieve trie acc i A in
          let acc = try_feature retrieve trie acc i B in
          all_symbols retrieve trie acc i
        | B ->
          let acc = try_feature retrieve trie acc i A in
          let acc = try_feature retrieve trie acc i B in
          let acc = try_feature retrieve trie acc i N in
          all_symbols retrieve trie acc i
        | N ->
          let acc = try_feature retrieve trie acc i B in
          try_feature retrieve trie acc i N
    in
    retrieve idx.trie acc 0

  let retrieve_generalizations ?(subst=S.empty ()) idx o_i t o_t acc f =
    let fingerprint = idx.fp t in
    let rec retrieve trie acc i =
      if i = Array.length fingerprint
        then Leaf.fold_match ~subst trie.leaf o_i t o_t acc f
      else
        let feat = fingerprint.(i) in
        match feat with
        | S s ->
          let acc = try_feature retrieve trie acc i feat in
          let acc = try_feature retrieve trie acc i A in
          try_feature retrieve trie acc i B
        | A ->
          let acc = try_feature retrieve trie acc i A in
          try_feature retrieve trie acc i B
        | B -> try_feature retrieve trie acc i B
        | N ->
          let acc = try_feature retrieve trie acc i B in
          try_feature retrieve trie acc i N
    in
    retrieve idx.trie acc 0

  let retrieve_specializations ?(subst=S.empty ()) idx o_i t o_t acc f = 
    let fingerprint = idx.fp t in
    let rec retrieve trie acc i =
      if i = Array.length fingerprint
        then Leaf.fold_matched ~subst trie.leaf o_i t o_t acc f
      else
        let feat = fingerprint.(i) in
        match feat with
        | S s -> try_feature retrieve trie acc i feat
        | A ->
          let acc = try_feature retrieve trie acc i A in
          all_symbols retrieve trie acc i
        | B ->
          let acc = try_feature retrieve trie acc i A in
          let acc = try_feature retrieve trie acc i B in
          let acc = try_feature retrieve trie acc i N in
          all_symbols retrieve trie acc i
        | N -> try_feature retrieve trie acc i N
    in
    retrieve idx.trie acc 0

  let to_dot buf t =
    failwith "Fingerprint: to_dot not implemented"
end
