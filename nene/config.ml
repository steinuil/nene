(*
let session_id_mutex = Lwt_mutex.create ()

let transmission_url =
  let port = with_default 9091 flags.transmission_port in
  let host = with_default "127.0.0.1" flags.transmission_host in
  Uri.make ~scheme:"http" ~port ~host ~path:"/transmission/rpc" ()

let session_id' : Cohttp.Header.t option ref = ref None

let session_id () =
  let%lwt () = Lwt_mutex.lock session_id_mutex in
  match !session_id' with
  | Some headers ->
    Lwt_mutex.unlock session_id_mutex;
    Lwt.return headers
  | None ->
    let%lwt resp, _ = Cohttp_lwt_unix.Client.get transmission_url in
    let headers = Cohttp_lwt.Response.headers resp in
    let header_name = "X-Transmission-Session-Id" in
    let session_id_hdr =
      match Cohttp.Header.get headers header_name with
      | Some id -> Cohttp.Header.init_with header_name id
      | None -> Cohttp.Header.init ()
    in
    session_id' := Some session_id_hdr;
    Lwt_mutex.unlock session_id_mutex;
    Lwt.return session_id_hdr

let resp_success = function "result", `String "success" -> true | _ -> false

let add_torrent url =
  let dl_dir =
    match flags.download_dir with
    | Some d -> [ ("download-dir", `String d) ]
    | None -> []
  in
  let json =
    `Assoc
      [
        ("method", `String "torrent-add");
        ("arguments", `Assoc (("filename", `String url) :: dl_dir));
      ]
  in
  let%lwt headers = session_id () in
  let body = Cohttp_lwt.Body.of_string @@ Yojson.to_string json in
  let%lwt _, body =
    Cohttp_lwt_unix.Client.post ~body ~headers transmission_url
  in
  let%lwt resp = Cohttp_lwt.Body.to_string body in
  match Yojson.Basic.from_string resp with
  | `Assoc assocs ->
    if List.exists resp_success assocs then Lwt.return ()
    else Lwt.fail (Failure "Couldn't add the torrent to transmission")
  | _ -> Lwt.fail (Failure "Couldn't add the torrent to transmission")
*)

type torrent = { filename : string; link : string }

type backend =
  | Directory of string
  | Transmission of { host : Uri.t; download_dir : string option }

type show_pattern = { name : string; pattern : Pattern.t }

type tracker = { rss_url : Uri.t; shows : show_pattern list }

type settings = { backend : backend; trackers : tracker list }

module File = struct
  open Patche.Combinators
  open Patche.Combinators.Infix
  open Patche.Json

  let regexp =
    assoc
      (map3
         (fun pattern episode_idx version_idx ->
           Pattern.compile_perl_regexp pattern ~episode_idx ~version_idx)
         (required "pattern" ->= string)
         (required "episode" ->= int)
         (required "version" ->= int))

  let show =
    assoc
      (map2
         (fun name pattern -> { name; pattern })
         (required "name" ->= string)
         (or_
            (required "regexp" ->= regexp)
            ( required "pattern" ->= string
            |> map_option ~none:(fun _ -> `Json_error "a") Pattern.compile )))

  let transmission_backend =
    assoc
      (map2
         (fun host download_dir ->
           Transmission { host = Uri.of_string host; download_dir })
         (required "host" ->= string)
         (let& ddir = optional "download_dir" in
          match ddir with
          | Some (`String s) -> return (Some s)
          | Some _ -> error (`Json_error "a")
          | None -> return None))

  let backend =
    assoc
      ( (required "directory" ->= string ->> fun dir -> Directory dir)
      <|> required "transmission" ->= transmission_backend )

  let tracker =
    assoc
      (map2
         (fun url shows -> { rss_url = Uri.of_string url; shows })
         (required "url" ->= string)
         (required "shows" ->= list_v show))

  let config =
    assoc
      (map2
         (fun backend trackers -> { backend; trackers })
         (required "backend" ->= backend)
         (required "trackers" ->= list_v tracker))

  let parse_json_exn json = config json |> Result.get_ok |> Option.some

  let parse_string str =
    try Yojson.Safe.from_string str |> parse_json_exn with _ -> None

  let parse_file str =
    try Yojson.Safe.from_file str |> parse_json_exn with _ -> None

  let%test _ =
    parse_string
      {|
    {
      "backend": {
        "transmission": {
          "host": "https://nyaa.si"
        }
      },
      "trackers": [
        {
          "url": "https://nyaa.si",
          "shows": [
            {
              "name": "Godzilla: Singular Point",
              "regexp": {
                "pattern": "[MoyaiSubs] Godzilla Singular Point - (\\d+) (\\[v(\\d+)\\]) .*\\.mkv",
                "episode": 1,
                "version": 3
              }
            },
            {
              "name": "Super Cub",
              "pattern": "[SubsPlease] Super Cub - <episode> (1080p) [**].mkv"
            }
          ]
        }
      ]
    }
    |}
    |> Option.get
    = {
        backend =
          Transmission
            { host = Uri.of_string "https://nyaa.si"; download_dir = None };
        trackers =
          [
            {
              rss_url = Uri.of_string "https://nyaa.si";
              shows =
                [
                  {
                    name = "Godzilla: Singular Point";
                    pattern =
                      {
                        regexp =
                          Re.Perl.compile_pat
                            {|[MoyaiSubs] Godzilla Singular Point - (\d+) (\[v(\d+)\]) .*\.mkv|};
                        episode_idx = 1;
                        version_idx = 3;
                      };
                  };
                  {
                    name = "Super Cub";
                    pattern =
                      Pattern.compile
                        "[SubsPlease] Super Cub - <episode> (1080p) [**].mkv"
                      |> Option.get;
                  };
                ];
            };
          ];
      }
end
