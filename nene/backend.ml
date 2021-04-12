type t = Config.torrent -> unit Lwt.t

let ( let* ) = Lwt.bind

let session_id_header_name = "X-Transmission-Session-Id"

let add_torrent_json torrent download_dir : Yojson.Safe.t =
  let dl_dir =
    match download_dir with
    | Some d -> [ ("download-dir", `String d) ]
    | None -> []
  in
  `Assoc
    [
      ("method", `String "torrent-add");
      ("arguments", `Assoc (("filename", `String torrent) :: dl_dir));
    ]

let make_transmission host download_dir : t =
  let new_session_id =
    let mutex = Lwt_mutex.create () in
    let session_id = ref None in
    fun () ->
      Lwt_mutex.lock mutex;%lwt
      match !session_id with
      | Some headers ->
          Lwt_mutex.unlock mutex;
          Lwt.return headers
      | None ->
          let* resp, _ = Cohttp_lwt_unix.Client.get host in
          let header =
            match
              Cohttp.Header.get
                (Cohttp_lwt_unix.Response.headers resp)
                session_id_header_name
            with
            | Some id -> Cohttp.Header.init_with session_id_header_name id
            | None -> Cohttp.Header.init ()
          in
          session_id := Some header;
          Lwt_mutex.unlock mutex;
          Lwt.return header
  in
  fun { title = _; link } ->
    let* headers = new_session_id () in
    let body =
      Cohttp_lwt.Body.of_string @@ Yojson.Safe.to_string
      @@ add_torrent_json link download_dir
    in
    let* _, body = Cohttp_lwt_unix.Client.post ~body ~headers host in
    let* body = Cohttp_lwt.Body.to_string body in
    match Yojson.Safe.from_string body with
    | `Assoc assocs
      when List.exists
             (function "result", `String "success" -> true | _ -> false)
             assocs ->
        Lwt.return ()
    | _ -> Lwt.fail (Failure "Couldn't add the torrent to transmission")

let from_cfg : Config.backend -> t = function
  | Config.Transmission { host; download_dir } ->
      make_transmission host download_dir
  | Directory _ -> failwith "a"
