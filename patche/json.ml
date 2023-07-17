type input = Yojson.Safe.t

type error =
  [ Combinators.error | `Json_error of string | `Trailing_elements_detected ]

type 'a t = input -> ('a, error) result

let null : unit t = function
  | `Null -> Ok ()
  | _ -> Error (`Json_error "expected uh")

let bool : bool t = function
  | `Bool b -> Ok b
  | _ -> Error (`Json_error "expected")

let int : int t = function
  | `Int i -> Ok i
  | _ -> Error (`Json_error "expected")

let intlit ~accept_int : string t = function
  | `Intlit i -> Ok i
  | `Int i when accept_int -> Ok (string_of_int i)
  | _ -> Error (`Json_error "expected")

let float : float t = function
  | `Float f -> Ok f
  | _ -> Error (`Json_error "expected")

let string : string t = function
  | `String s -> Ok s
  | _ -> Error (`Json_error "expected")

let ( let* ) = Result.bind

open Unordered.Parsers

let run p inp =
  let* v, inp = p inp in
  let* (), _ = eoi inp in
  Ok v

let list p : 'a t = function
  | `List l -> run p l
  | _ -> Error (`Json_error "expected")

let list_v p : 'a list t = function
  | `List l ->
      let rec loop acc = function
        | [] -> Ok (List.rev acc)
        | item :: rest -> (
            match p item with
            | Ok v -> loop (v :: acc) rest
            | Error _ as err -> err)
      in
      loop [] l
  | _ -> Error (`Json_error "e")

let named name = function n, v when n = name -> Some v | _ -> None

let required name ls =
  match list_remove_opt (named name) ls with
  | Some v, rest -> Ok (v, rest)
  | None, _ -> Error (`Json_error "a")

let optional name ls =
  match list_remove_opt (named name) ls with
  | Some v, rest -> Ok (Some v, rest)
  | None, rest -> Ok (None, rest)

let assoc p : 'a t = function
  | `Assoc assocs -> run p assocs
  | _ -> Error (`Json_error "a")

let or_v p1 p2 inp = match p1 inp with Ok v -> Ok v | Error _ -> p2 inp
