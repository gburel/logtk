
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

(** {1 LogtkPositions in terms, clauses...} *)

type t =
  | Stop
  | LogtkType of t       (** Switch to type *)
  | Left of t       (** Left term in curried application *)
  | Right of t      (** Right term in curried application *)
  | Record_field of string * t  (** Field of a record *)
  | Record_rest of t  (** Extension part of the record *)
  | Head of t       (** Head of uncurried term *)
  | Arg of int * t  (** argument term in uncurried term, or in multiset *)
  (** A position is a path in a tree *)

type position = t

let stop = Stop
let type_ pos = LogtkType pos
let left pos = Left pos
let right pos = Right pos
let record_field name pos = Record_field (name, pos)
let record_rest pos = Record_rest pos
let head pos = Head pos
let arg i pos = Arg (i, pos)

let compare = Pervasives.compare
let eq p1 p2 = compare p1 p2 = 0
let hash p = Hashtbl.hash p

let rev pos =
  let rec rev acc pos = match pos with
  | Stop -> acc
  | LogtkType pos' -> rev (LogtkType acc) pos'
  | Left pos' -> rev (Left acc) pos'
  | Right pos' -> rev (Right acc) pos'
  | Record_field (n,pos') -> rev (Record_field (n,acc)) pos'
  | Record_rest pos' -> rev (Record_rest acc) pos'
  | Head pos' -> rev (Head acc) pos'
  | Arg (i, pos') -> rev (Arg (i,acc)) pos'
  in rev Stop pos

let opp = function
  | Left p -> Right p
  | Right p -> Left p
  | pos -> pos

(* Recursive append *)
let rec append p1 p2 = match p1 with
  | Stop -> p2
  | LogtkType p1' -> LogtkType (append p1' p2)
  | Left p1' -> Left (append p1' p2)
  | Right p1' -> Right (append p1' p2)
  | Record_field(name, p1') -> Record_field(name,append p1' p2)
  | Record_rest p1' -> Record_rest (append p1' p2)
  | Head p1' -> Head (append p1' p2)
  | Arg(i, p1') -> Arg (i,append p1' p2)

let rec pp buf pos = match pos with
  | Stop -> Buffer.add_string buf "ε"
  | Left p' -> Buffer.add_string buf "←."; pp buf p'
  | Right p' -> Buffer.add_string buf "→."; pp buf p'
  | LogtkType p' -> Buffer.add_string buf "τ."; pp buf p'
  | Record_field (name,p') ->
    Printf.bprintf buf "{%s}." name; pp buf p'
  | Record_rest p' -> Buffer.add_string buf "{|}."; pp buf p'
  | Head p' -> Buffer.add_string buf "@."; pp buf p'
  | Arg (i,p') -> Printf.bprintf buf "%d." i; pp buf p'

let to_string pos =
  let b = Buffer.create 16 in
  pp b pos;
  Buffer.contents b

let fmt fmt pos =
  Format.pp_print_string fmt (to_string pos)

(** {2 LogtkPosition builder}

We use an adaptation of difference lists for this tasks *)

module Build = struct
  type t =
    | E (** Empty (identity function) *)
    | P of position * t (** Pre-pend given position, then apply previous builder *)
    | N of (position -> position) * t
      (** Apply function to position, then apply linked builder *)

  let empty = E

  let of_pos p = P (p, E) 

  (* how to apply a difference list to a tail list *)
  let rec __apply tail b = match b with
    | E -> tail 
    | P (pos0,b') -> __apply (append pos0 tail) b'
    | N (f, b') -> __apply (f tail) b'

  let to_pos b = __apply stop b

  let suffix b pos =
    (* given a suffix, first append pos to it, then apply b *)
    N ((fun pos0 -> append pos pos0), b)

  let prefix pos b =
    (* tricky: this doesn't follow the recursive structure. Hence we
        need to first apply b totally, then pre-prend pos *)
    N ((fun pos1 -> append pos (__apply pos1 b)), E)

  let left b = N (left, b)
  let right b = N (right, b)
  let type_ b = N (type_, b)
  let record_field n b = N (record_field n, b)
  let record_rest b = N (record_rest, b)
  let head b = N(head, b)
  let arg i b = N(arg i, b)

  let pp buf t = pp buf (to_pos t)
  let fmt formatter t = fmt formatter (to_pos t)
end
