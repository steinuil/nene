open Lwt


(* RSS downloader *)
let downloader =
  "curl"


type torrent =
  { title : string
  ; link  : string }


let fetch_torrents url : (torrent list) Lwt.t =
  let open Xml in
  let rec torrents_of_item = function
    | (Some title, Some link), _ ->
      { title = title; link = link }
    | (_, l), Element ("title", _, [PCData title]) :: rest ->
      torrents_of_item ((Some title, l), rest)
    | (t, _), Element ("link", _, [PCData link]) :: rest ->
      torrents_of_item ((t, Some link), rest)
    | tup, _ :: rest ->
      torrents_of_item (tup, rest)
    | (None, None), [] | (None, Some _), [] | (Some _, None), [] ->
      raise (Failure "no item title or link")
  in
  let fold_items acc = function
    | Element ("item", _, children) ->
        torrents_of_item ((None, None), children) :: acc
    | _ -> acc
  in
  let cmd = downloader, [|"nene-fetch"; url|] in
  Lwt_process.pread ~stderr:`Dev_null cmd >|= fun str ->
  match parse_string str with
  | Element ("rss", _, [Element ("channel", _, children)]) ->
      List.fold_left fold_items [] children
  | _ -> raise (Failure "not an rss document")



(* *)
let shows_file =
  "shows.scm"


let load_shows () : (string * (string * Str.regexp) list) list =
  let open Sexplib.Conv in
  let decoder =
    pair_of_sexp string_of_sexp
      (list_of_sexp
        (pair_of_sexp string_of_sexp string_of_sexp))
  in Sexplib.Sexp.load_sexps_conv_exn shows_file decoder
  |> List.map (fun (url, shows) -> url, List.map
    (fun (name, reg) -> name, Str.regexp reg) shows)



(* *)
let seen_file =
  "seen.scm"


let load_seen () : (string * (int * int) list) list =
  let open Sexplib.Conv in
  let decoder =
    pair_of_sexp string_of_sexp
      (list_of_sexp
        (pair_of_sexp int_of_sexp int_of_sexp))
  in Sexplib.Sexp.load_sexps_conv_exn seen_file decoder



(* *)
let version_of_title reg title =
  try
    let v = Str.replace_first reg "\\2" title in
    let len = String.length v in
    String.sub v 1 (len - 1) |> int_of_string
  with Failure _ -> 1


let list_update (assoc : 'a) (nw : 'b) (ls : ('a * 'b) list) =
  List.remove_assoc assoc ls |>
  List.cons (assoc, nw)


let one name reg = fun seen { title; link } ->
  if Str.string_match reg title 0 then
    let num = Str.replace_first reg "\\1" title |> int_of_string in
    let ver = version_of_title reg title in
    (* FIXME: this horrible control flow *)
    try let eps = List.assoc name seen in
      try let curr = List.assoc num eps in
        if ver > curr then
          (* Download here *)
          let new_eps = list_update num ver eps in
          print_endline @@ name ^ " " ^ string_of_int num;
          list_update name new_eps seen
        else seen
      with Not_found ->
        print_endline @@ name ^ " " ^ string_of_int num;
        list_update name ((num, ver) :: eps) seen
    with Not_found ->
      print_endline @@ name ^ " " ^ string_of_int num;
      (name, [num, ver]) :: seen
  else seen


let stuff () =
  let url_shows = load_shows () in
  let seen = load_seen () in
  Lwt_list.map_p (fun (rss_url, shows) ->
    fetch_torrents rss_url >|= fun torrents ->
    List.fold_left (fun seen (name, reg) ->
      List.fold_left (one name reg) seen torrents)
      seen shows) url_shows >|= fun _ -> ()


let die msg =
  prerr_string "\x1b[31;40m";
  prerr_string msg;
  prerr_string "\x1b[0m\n"


let () =
  Lwt_main.run @@ stuff ()
