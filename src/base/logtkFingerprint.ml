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


(** {1 Fingerprint term indexing} *)

module T = LogtkFOTerm
module ST = LogtkScopedTerm
module I = LogtkIndex
module S = LogtkSubsts

let prof_traverse = LogtkUtil.mk_profiler "fingerprint.traverse"

(** a feature *)
type feature = A | B | N | S of LogtkSymbol.t

(** a fingerprint function, it computes several features of a term *)
type fingerprint_fun = T.t -> feature list

(* TODO: use a feature array, rather than a list *)

(* TODO: more efficient implem of traversal, only following branches that
  are useful instead of folding and filtering *)

(** compute a feature for a given position *)
let rec gfpf pos t = match pos, T.Classic.view t with
  | [], T.Classic.Var _ -> A
  | [], T.Classic.BVar _ -> S (LogtkSymbol.of_string "__de_bruijn")
  | [], T.Classic.App (s, _, _) -> S s
  | i::pos', T.Classic.App (_, _, l) ->
    begin try gfpf pos' (List.nth l i)  (* recurse in subterm *)
    with Failure _ -> N  (* not a position in t *)
    end
  | _::_, T.Classic.BVar _ -> N
  | _::_, T.Classic.Var _ -> B  (* under variable *)
  | _, T.Classic.NonFO -> B (* don't filter! *)

(* TODO more efficient way to compute a vector of features: if the fingerprint
   is in BFS, compute features during only one traversal of the term? *)

(** compute a feature vector for some positions *)
let fp positions =
  (* list of fingerprint feature functions *)
  let fpfs = List.map (fun pos -> gfpf pos) positions in
  fun t ->
    List.map (fun fpf -> fpf t) fpfs

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

(** {2 LogtkIndex construction} *)

let __feat2int = function
  | A -> 0
  | B -> 1
  | S _ -> 2
  | N -> 3

let cmp_feature f1 f2 = match f1, f2 with
  | A, A
  | B, B
  | N, N -> 0
  | S s1, S s2 -> LogtkSymbol.cmp s1 s2
  | _ -> __feat2int f1 - __feat2int f2

(** check whether two features are compatible for unification. *)
let compatible_features_unif f1 f2 =
  match f1, f2 with
  | S s1, S s2 -> LogtkSymbol.eq s1 s2
  | B, _ | _, B -> true
  | A, N | N, A -> false
  | A, _ | _, A -> true
  | N, S _ | S _, N -> false
  | N, N -> true

(** check whether two features are compatible for matching. *)
let compatible_features_match f1 f2 =
  match f1, f2 with
  | S s1, S s2 -> LogtkSymbol.eq s1 s2
  | B, _ -> true
  | N, N -> true
  | N, _ -> false
  | _, N -> false
  | A, B -> false
  | A, _ -> true
  | S _, _ -> false

(** Map whose keys are features *)
module FeatureMap = Map.Make(struct
  type t = feature
  let compare = cmp_feature
end)

module Make(X : Set.OrderedType) = struct
  type elt = X.t

  module Leaf = LogtkIndex.MakeLeaf(X)

  type t = {
    trie : trie;
    fp : fingerprint_fun;
  }
  and trie =
    | Empty
    | Node of trie FeatureMap.t
    | Leaf of Leaf.t
    (** The index *)

  let default_fp = fp7m

  let empty () = {
    trie = Empty;
    fp = default_fp;
  }

  let empty_with fp = {
    trie = Empty;
    fp;
  }

  let get_fingerprint idx = idx.fp

  let name = "fingerprint_idx"

  let is_empty idx =
    let rec is_empty trie =
      match trie with
      | Empty -> true
      | Leaf l -> Leaf.is_empty l
      | Node map -> FeatureMap.for_all (fun _ trie' -> is_empty trie') map
    in is_empty idx.trie

  (** add t -> data to the trie *)
  let add idx t data =
    (* recursive insertion *)
    let rec recurse trie features =
      match trie, features with
      | Empty, [] ->
        let leaf = Leaf.empty in
        let leaf = Leaf.add leaf t data in
        Leaf leaf (* creation of new leaf *)
      | Empty, f::features' ->
        let subtrie = recurse Empty features' in
        let map = FeatureMap.add f subtrie FeatureMap.empty in
        Node map  (* index new subtrie by feature *)
      | Node map, f::features' ->
        let subtrie =
          try FeatureMap.find f map
          with Not_found -> Empty in
        (* insert in subtrie *)
        let subtrie = recurse subtrie features' in
        let map = FeatureMap.add f subtrie map in
        Node map  (* point to new subtrie *)
      | Leaf leaf, [] ->
        let leaf = Leaf.add leaf t data in
        Leaf leaf (* addition to set *)
      | Node _, [] | Leaf _, _::_ ->
        failwith "different feature length in fingerprint trie"
    in
    let features = idx.fp t in  (* features of term *)
    { idx with trie = recurse idx.trie features; }

  (** remove t -> data from the trie *)
  let remove idx t data =
    (* recursive deletion *)
    let rec recurse trie features =
      match trie, features with
      | Empty, [] | Empty, _::_ ->
        Empty (* keep it empty *)
      | Node map, f::features' ->
        let map =
          (* delete from subtrie, if there is a subtrie *)
          try
            let subtrie = FeatureMap.find f map in
            let subtrie = recurse subtrie features' in
            if subtrie = Empty
              then FeatureMap.remove f map
              else FeatureMap.add f subtrie map
          with Not_found -> map
        in
        (* if the map is empty, use Empty *)
        if FeatureMap.is_empty map
          then Empty
          else Node map
      | Leaf leaf, [] ->
        let leaf = Leaf.remove leaf t data in
        if Leaf.is_empty leaf
          then Empty
          else Leaf leaf
      | Node _, [] | Leaf _, _::_ ->
        failwith "different feature length in fingerprint trie"
    in
    let features = idx.fp t in  (* features of term *)
    { idx with trie = recurse idx.trie features; }

  let iter idx f =
    let rec iter trie f = match trie with
      | Empty -> ()
      | Node map -> FeatureMap.iter (fun _ subtrie -> iter subtrie f) map
      | Leaf leaf -> Leaf.iter leaf f
    in
    iter idx.trie f

  let fold idx f acc =
    let rec fold trie f acc = match trie with
      | Empty -> acc
      | Node map -> FeatureMap.fold (fun _ subtrie acc -> fold subtrie f acc) map acc
      | Leaf leaf -> Leaf.fold leaf acc f
    in
    fold idx.trie f acc

  (** number of indexed terms *)
  let size idx =
    let n = ref 0 in
    iter idx (fun _ _ -> incr n);
    !n

  (** fold on parts of the trie that are compatible with features *)
  let traverse ~compatible idx features acc k =
    LogtkUtil.enter_prof prof_traverse;
    (* fold on the trie *)
    let rec recurse trie features acc =
      match trie, features with
      | Empty, _ -> acc
      | Leaf leaf, [] ->
        k acc leaf  (* give the leaf to [k] *)
      | Node map, f::features' ->
        (* fold on any subtrie that is compatible with current feature *)
        FeatureMap.fold
          (fun f' subtrie acc ->
            if compatible f f'
              then recurse subtrie features' acc 
              else acc)
          map acc
      | Node _, [] | Leaf _, _::_ ->
        failwith "different feature length in fingerprint trie"
    in
    try
      let acc = recurse idx.trie features acc in
      LogtkUtil.exit_prof prof_traverse;
      acc
    with e ->
      LogtkUtil.exit_prof prof_traverse;
      raise e

  let retrieve_unifiables ?(subst=S.empty) idx o_i t o_t acc f =
    let features = idx.fp t in
    let compatible = compatible_features_unif in
    traverse ~compatible idx features acc
      (fun acc leaf -> Leaf.fold_unify ~subst leaf o_i t o_t acc f)

  let retrieve_generalizations ?(allow_open=false) ?(subst=S.empty) idx o_i t o_t acc f =
    let features = idx.fp t in
    (* compatible t1 t2 if t2 can match t1 *)
    let compatible f1 f2 = compatible_features_match f2 f1 in
    traverse ~compatible idx features acc
      (fun acc leaf -> Leaf.fold_match ~allow_open ~subst leaf o_i t o_t acc f)

  let retrieve_specializations ?(allow_open=false) ?(subst=S.empty) idx o_i t o_t acc f =
    let features = idx.fp t in
    let compatible = compatible_features_match in
    traverse ~compatible idx features acc
      (fun acc leaf -> Leaf.fold_matched ~allow_open ~subst leaf o_i t o_t acc f)

  let to_dot buf t =
    failwith "Fingerprint: to_dot not implemented"
end
