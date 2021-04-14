type el = string * tree list

and tree = El of el | Data of string

exception Invalid_feed

let parse_xml source =
  let inp = Xmlm.make_input ~strip:true source in
  let el ((_, name), _) children = El (name, children) in
  let data str = Data str in
  match Xmlm.input_doc_tree ~el ~data inp with
  | _, tree -> tree
  | exception Xmlm.Error _ -> raise Invalid_feed
  | exception Invalid_argument _ -> raise Invalid_feed

let rss_channel = function
  | El ("rss", [ El ("channel", children) ]) -> children
  | _ -> raise Invalid_feed

let rss_item = function El ("item", children) -> Some children | _ -> None

let rec item_to_torrent = function
  | _, (Some filename, Some link) -> Config.{ filename; link }
  | El ("title", [ Data filename ]) :: rest, (_, link) ->
      item_to_torrent (rest, (Some filename, link))
  | El ("link", [ Data link ]) :: rest, (title, _) ->
      item_to_torrent (rest, (title, Some link))
  | _ :: rest, info -> item_to_torrent (rest, info)
  | [], _ -> raise Invalid_feed

let item_to_torrent children = item_to_torrent (children, (None, None))

let torrents_from source =
  try
    parse_xml source |> rss_channel |> List.filter_map rss_item
    |> List.map item_to_torrent |> Option.some
  with Invalid_feed -> None

let torrents_from_channel chan = torrents_from (`Channel chan)

let torrents_from_string txt = torrents_from (`String (0, txt))
