
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

(** {1 Unification and Matching} *)

type scope = Substs.scope
type subst = Substs.t

(** {2 Result of (multiple) Unification} *)

module Res : sig
  type t =
    | End
    | Ok of subst * (unit -> t)
    (** Result of unification provides a continuation to get other
     * substitutions, in case the unification is n-ary. *)

  val all : t -> subst list
    (** Compute all results into a list *)

  val to_seq : t -> subst Sequence.t
    (** Iterate on results *)
end

exception Fail
  (** Raised when a unification/matching attempt fails *)

(** {2 Signatures} *)

module type UNARY = sig
  type term

  val unification : ?subst:subst -> term -> scope -> term -> scope -> subst
    (** Unify terms, returns a subst or
        @raise Fail if the terms are not unifiable *)

  val matching : ?subst:subst -> pattern:term -> scope -> term -> scope -> subst
    (** [matching ~pattern scope_p b scope_b] returns
        [sigma] such that [sigma pattern = b], or fails.
        Only variables from the scope of [pattern] can  be bound in the subst.
        @raise Fail if the terms do not match.
        @raise Invalid_argument if the two scopes are equal *)

  val matching_same_scope : ?subst:subst -> scope:scope -> pattern:term -> term -> subst
    (** matches [pattern] (more general) with the other term.
     * The two terms live in the same scope, which is passed as the
     * [scope] argument. *)

  val variant : ?subst:subst -> term -> scope -> term -> scope -> subst
    (** Succeeds iff the first term is a variant of the second, ie
        if they are alpha-equivalent *)

  val are_unifiable : term -> term -> bool

  val matches : pattern:term -> term -> bool

  val are_variant : term -> term -> bool
end

module type NARY = sig
  type term
  type result = Res.t

  val unification : ?subst:subst -> term -> scope -> term -> scope -> result
    (** unification of two terms *)

  val matching : ?subst:subst -> pattern:term -> scope -> term -> scope -> result
    (** matching of two terms.
     * @raise Invalid_argument if the two scopes are equal. *)

  val variant : ?subst:subst -> term -> scope -> term -> scope -> result
    (** alpha-equivalence checking of two terms *)

  val are_unifiable : term -> term -> bool

  val matches : pattern:term -> term -> bool

  val are_variant : term -> term -> bool
end

(** {2 Base (scoped terms)} *)

include NARY with type term = ScopedTerm.t

(** {2 Specializations} *)

module Ty : UNARY with type term = Type.t
module FO : UNARY with type term = FOTerm.t
module HO : NARY with type term = HOTerm.t

(** {2 Formulas} *)

module Form : sig
  val variant : ?subst:subst ->
                Formula.FO.t -> scope -> Formula.FO.t -> scope ->
                Res.t

  val are_variant : Formula.FO.t -> Formula.FO.t -> bool
end

