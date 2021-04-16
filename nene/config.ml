type torrent = { filename : string; link : string }

let pp_torrent out { filename; link } =
  Format.fprintf out "{ filename = %S; link = %S }" filename link

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
