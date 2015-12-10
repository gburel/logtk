
(* This file is free software, part of Logtk. See file "license" for more details. *)

(** {1 Reduction to CNF and simplifications} *)

type term = TypedSTerm.t
type form = TypedSTerm.t

(** See "computing small normal forms", in the handbook of automated reasoning.
    All transformations are made on curried terms and formulas. *)

exception Error of string

val miniscope : ?distribute_exists:bool -> form -> form
(** Apply miniscoping transformation to the term.
    @param distribute_exists see whether ?X:(p(X)|q(X)) should be
      transformed into (?X: p(X) | ?X: q(X)). Default: [false] *)

type lit =
  | True
  | False
  | Atom of term * bool
  | Eq of term * term
  | Neq of term * term

type clause = lit list
(** Basic clause representation, as list of literals *)

(** Options are used to tune the behavior of the CNF conversion. *)
type options =
  | DistributeExists
  (** if enabled, will distribute existential quantifiers over
      disjunctions. This can make skolem symbols smaller (smaller arity) but
      introduce more of them. *)

  | DisableRenaming
  (** disables formula renaming. Can re-introduce the worst-case
      exponential behavior of CNF. *)

  | InitialProcessing of (form -> form)
  (** any processing, at the beginning, before CNF starts  *)

  | PostNNF of (form -> form)
  (** any processing that keeps negation at leaves,
      just after reduction to NNF. Its output
      must not break the NNF form (negation at root only). *)

  | PostSkolem of (form -> form)
  (** transformation applied just after skolemization. It must not
      break skolemization nor NNF (no quantifier, no non-leaf negation). *)

val cnf_of :
  ?opts:options list ->
  ?ctx:Skolem.ctx ->
  form ->
  (clause, CCVector.ro) CCVector.t
(** Transform the clause into proper CNF; returns a list of clauses.
    Options are used to tune the behavior. *)

val cnf_of_seq :
  ?opts:options list -> ?ctx:Skolem.ctx ->
  form Sequence.t ->
  (clause, CCVector.ro) CCVector.t
