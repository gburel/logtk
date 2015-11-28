
(* This file is free software, part of Logtk. See file "license" for more details. *)

(** {1 Variable} *)

type 'a t = {
  id: ID.t;
  ty: 'a;
}
type 'a var = 'a t

let make ~ty id = {ty; id; }

let of_string ~ty name = {ty; id=ID.make name; }

let gensym ~ty () = {ty; id=ID.gensym(); }

let copy v = make ~ty:v.ty (ID.copy v.id)

let update_ty v ~f = {v with ty=f v.ty; }

let ty t = t.ty
let id t = t.id

let compare a b = ID.compare a.id b.id
let equal a b = ID.equal a.id b.id
let hash a = ID.hash a.id
let hash_fun a = ID.hash_fun a.id

let pp out a = ID.pp out a.id
let to_string a = ID.to_string a.id

module Set = struct
  type 'a t = 'a var ID.Map.t
  let empty = ID.Map.empty
  let add t v = ID.Map.add v.id v t
  let mem t v = ID.Map.mem v.id t
  let find_exn t id = ID.Map.find id t
  let find t id = try Some (find_exn t id) with Not_found -> None
  let cardinal t = ID.Map.cardinal t
  let of_seq s = s |> Sequence.map (fun v->v.id, v) |> ID.Map.of_seq
  let to_seq t = ID.Map.to_seq t |> Sequence.map snd
  let to_list t = ID.Map.fold (fun _ v acc ->v::acc) t []
  let pp out t =
    CCFormat.seq ~start:"" ~stop:"" ~sep:", " pp out (to_seq t)
end