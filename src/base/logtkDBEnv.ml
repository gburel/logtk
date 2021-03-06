
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

(** {1 De Bruijn environments} *)

type 'a t = {
  size : int;
  stack : 'a option list;
}

let empty = { size=0; stack=[]; }

let is_empty env = env.size = 0

let make size = {
  size;
  stack = CCList.range 0 size |> List.map (fun _ -> None);
}

let singleton x = { size=1; stack = [Some x]; }

let push env x = {size=env.size+1; stack=(Some x) :: env.stack; }

let push_none env =  {size=env.size+1; stack=None :: env.stack; }

let rec push_none_multiple env n =
  if n <= 0 then env else push_none (push_none_multiple env (n-1))

let size env = env.size

let pop env = match env.stack with
  | [] -> raise (Invalid_argument "Env.pop: empty env")
  | _::tl -> {size=env.size-1; stack=tl; }

let rec pop_many env n = match n with
  | 0 -> env
  | _ -> pop_many (pop env) (n-1)

let find env n =
  if n < env.size then List.nth env.stack n else None

let find_exn env n =
  if n < env.size
    then match List.nth env.stack n with
      | None -> failwith "LogtkDBEnv.find_exn"
      | Some x -> x
    else failwith "LogtkDBEnv.find_exn"

let mem env n =
  if n < env.size then List.nth env.stack n <> None else false

let set env n x =
  if n<0 || n >= env.size then raise (Invalid_argument "LogtkDBEnv.set");
  {env with stack= CCList.Idx.set env.stack n (Some x); }

let num_bindings db =
  let rec count acc l = match l with
    | [] -> acc
    | None :: l' -> count acc l'
    | Some _ :: l' -> count (1+acc) l'
  in count 0 db.stack

let map f db =
  let stack = List.map
    (function
       | None -> None
       | Some x -> Some (f x))
    db.stack
  in
  { db with stack; }

let of_list l =
  let max = List.fold_left (fun acc (b,_) -> max acc b) ~-1 l in
  let env = make (max+1) in
  List.fold_left
    (fun env (db, v) -> set env db v)
    env l

type 'a printer = Format.formatter -> 'a -> unit

let print pp_x out e =
  let pp_item out = function
    | None -> Format.pp_print_string out "_"
    | Some x -> Format.fprintf out "[%a]" pp_x x
  in
  Format.fprintf out "@[<hv2>%a@]" (CCList.print pp_item) e.stack
