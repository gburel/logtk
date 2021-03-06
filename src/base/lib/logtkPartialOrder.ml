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

(** {1 Partial LogtkOrdering on symbols} *)

module type S = LogtkPartialOrder_intf.S

(** {2 Helper: boolean matrix}

The matrix is *)

module BoolMatrix = struct
  type t = {
    bv : bool array;
    line : int; (* number of lines *)
    column : int; (* number of columns *)
  }

  (* matrix of size (line,column) *)
  let create line column =
    let n = line * column in
    let bv = Array.make n false in
    { bv; line; column; }

  let copy m = { m with bv=Array.copy m.bv; }

  (* index of m[i,j]. [i] is the line number. *)
  let _idx m i j =
    m.column * i + j

  let set m i j = m.bv.(_idx m i j) <- true

  let get m i j = m.bv.(_idx m i j)

  (* assuming the dimensions of m2 are >= those of m1, transfer content
      of m1 to m2 *)
  let transfer m1 m2 =
    assert (m1.line <= m2.line);
    assert (m1.column <= m2.column);
    for i = 0 to m1.line -1 do
      for j = 0 to m1.column -1 do
        if get m1 i j then set m2 i j
      done
    done
end

(** {2 Functor Implementation} *)

module type ELEMENT = sig
  type t

  val eq : t -> t -> bool
    (** Equality function on elements *)

  val hash : t -> int
    (** Hashing on elements *)
end

module Make(E : ELEMENT) = struct
  type elt = E.t

  (* hashtable on elements *)
  module H = Hashtbl.Make(struct
    type t = E.t
    let equal = E.eq
    let hash = E.hash
  end)

  (* the partial order is the adjacency matrix of a DAG *)
  type t = {
    tbl : int H.t; (* element -> index *)
    elements : elt array; (* index -> element *)
    mutable total : bool; (* is the order total? *)
    size : int; (* number of symbols in the table *)
    cmp : BoolMatrix.t; (* adjacency matrix *)
  }

  let create elements =
    let tbl = H.create 15 in
    (* remove replicate on the fly, by building a list of non-duplicated
      elements by decreasing index. *)
    let n = ref 0 in
    let elements = List.fold_left
      (fun acc e ->
        if not (H.mem tbl e) then begin
          H.replace tbl e !n;
          incr n;
          e :: acc
        end else acc)
      [] elements
    in
    let elements = Array.of_list (List.rev elements) in
    Array.iteri (fun i e -> assert (H.find tbl e = i)) elements;
    let size = H.length tbl in
    let cmp = BoolMatrix.create size size in
    { elements; tbl; size; cmp; total=false; }

  (* most of the PO is immutable after construction, so only copy the
      mutable part *)
  let copy po =
    { po with cmp = BoolMatrix.copy po.cmp; }

  let size po = po.size

  (* copy with more elements *)
  let extend po elements' =
    (* extend po.elements but keeping the same indexes *)
    let elements' = List.filter (fun x -> not (H.mem po.tbl x)) elements' in
    let elements = Array.of_list (Array.to_list po.elements @ elements') in
    (* same as {!create} *)
    let tbl = H.create (Array.length elements) in
    Array.iteri (fun i e -> H.replace tbl e i) elements;
    let size = H.length tbl in
    let cmp = BoolMatrix.create size size in
    (* transfer content of po.cmp to cmp *)
    BoolMatrix.transfer po.cmp cmp;
    { elements; tbl; size; cmp; total=false; }

  exception Unordered of int * int
  exception Eq of int * int

  (* check whether the ordering is total *)
  let _check_is_total po =
    let n = po.size in
    for i = 0 to n-1 do
      for j = i+1 to n-1 do
        let b_i_j = BoolMatrix.get po.cmp i j in
        let b_j_i = BoolMatrix.get po.cmp j i in
        if b_i_j && b_j_i then raise (Eq (i,j));
        if (not b_i_j) && not b_j_i then raise (Unordered (i,j));
        (* pair of elements that are equal or incomparable *)
      done;
    done

  let is_total po =
    po.total ||
    begin
      try
        _check_is_total po;
        po.total <- true;
        true
      with Unordered _ | Eq _ ->
        false
    end

  let is_total_details po =
    try
      _check_is_total po;
      `total
    with Unordered (i,j) -> `unordered (po.elements.(i),po.elements.(j))
    | Eq (i,j) -> `eq (po.elements.(i),po.elements.(j))

  (* update the transitive closure where i>j has just been added. *)
  let _propagate po i j =
    assert (i <> j);
    let n = po.size in
    let cmp = po.cmp in
    (* propagate recursively *)
    let rec propagate i j =
      if i = j || BoolMatrix.get cmp i j
      then () (* stop, already propagated *)
      else begin
        BoolMatrix.set cmp i j;
        for k = 0 to n-1 do
          (* k > i and i > j => k > j *)
          if k <> i && BoolMatrix.get cmp k i
            then propagate k j;
          (* i > j and j > k => i > k *)
          if k <> j && BoolMatrix.get cmp j k
            then propagate i k
        done;
      end
    in propagate i j

  (* enrich ordering with the given ordering function *)
  let enrich po cmp_fun =
    if po.total then ()
    else
      let n = po.size in
      let cmp = po.cmp in
      (* look for pairs that are not ordered *)
      for i = 0 to n - 1 do
        for j = i + 1 to n - 1 do
          if not (BoolMatrix.get cmp i j) && not (BoolMatrix.get cmp j i) then
            (* elements i and j not ordered, order them by cmp_fun
               and then re-compute the transitive closure *)
            match cmp_fun po.elements.(i) po.elements.(j) with
            | LogtkComparison.Incomparable -> ()
            | LogtkComparison.Eq ->
              _propagate po i j;
              _propagate po j i
            | LogtkComparison.Lt ->
              _propagate po j i
            | LogtkComparison.Gt ->
              _propagate po i j
        done;
      done

  let complete po cmp_fun =
    enrich po
      (fun x y ->
        match cmp_fun x y with
        | 0 -> LogtkComparison.Incomparable  (* see the .mli file *)
        | n when n < 0 -> LogtkComparison.Lt
        | _ -> LogtkComparison.Gt)

  (* compare two elements *)
  let compare po x y =
    let i = H.find po.tbl x in
    let j = H.find po.tbl y in
    match BoolMatrix.get po.cmp i j, BoolMatrix.get po.cmp j i with
    | false, false -> LogtkComparison.Incomparable
    | true, true -> LogtkComparison.Eq
    | true, false -> LogtkComparison.Gt
    | false, true -> LogtkComparison.Lt

  let pairs po =
    let acc = ref [] in
    for i = 0 to po.size -1 do
      for j = 0 to po.size -1 do
        if i<>j && BoolMatrix.get po.cmp i j
          then acc := (po.elements.(i), po.elements.(j)) :: !acc
      done
    done;
    !acc

  let elements po =
    let l = Array.to_list po.elements in
    (* sort in {b decreasing} order *)
    List.fast_sort
      (fun x y -> LogtkComparison.to_total (compare po y x))
      l
end
