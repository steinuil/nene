open Lwt.Syntax

exception Add_torrent_failure of string

exception Request_error

module Transmission = struct
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

  let response_result = function
    | `Assoc resp ->
        List.find_map
          (function "result", `String s -> Some s | _ -> None)
          resp
    | _ -> None

  let make_session_id_generator host =
    let mutex = Lwt_mutex.create () in
    object (self)
      val mutable session_id = None

      method set_from_response resp =
        let header =
          let headers = Cohttp_lwt_unix.Response.headers resp in
          match Cohttp.Header.get headers session_id_header_name with
          | Some id -> Cohttp.Header.init_with session_id_header_name id
          | None -> Cohttp.Header.init ()
        in
        session_id <- Some header;
        header

      method get =
        let* () = Lwt_mutex.lock mutex in
        let* header =
          match session_id with
          | Some header -> Lwt.return header
          | None ->
              let* resp, _ = Cohttp_lwt_unix.Client.get host in
              Lwt.return (self#set_from_response resp)
        in
        Lwt_mutex.unlock mutex;
        Lwt.return header
    end

  let make_backend host download_dir =
    let session_id = make_session_id_generator host in
    let rec add_torrent Config.({ filename = _; link } as torrent) =
      let* headers = session_id#get in
      let body =
        add_torrent_json link download_dir
        |> Yojson.Safe.to_string |> Cohttp_lwt.Body.of_string
      in
      let* resp, body = Cohttp_lwt_unix.Client.post ~body ~headers host in
      if resp.status = `Conflict then
        let _ = session_id#set_from_response resp in
        add_torrent torrent
      else
        let* body =
          let* body = Cohttp_lwt.Body.to_string body in
          try Yojson.Safe.from_string body |> Lwt.return
          with Yojson.Safe.Finally _ -> Lwt.fail Request_error
        in
        match response_result body with
        | Some "success" -> Lwt.return_unit
        | Some error -> Lwt.fail (Add_torrent_failure error)
        | None -> Lwt.fail Request_error
    in
    fun torrent ->
      try%lwt add_torrent torrent with
      | (Add_torrent_failure _ | Request_error) as exn -> Lwt.fail exn
      | _ -> Lwt.fail Request_error
end

(** @raise Add_torrent_failure when Transmission returns an error message
    @raise Request_error when an error occurs during the request *)
let from_cfg = function
  | Config.Transmission { host; download_dir } ->
      Transmission.make_backend host download_dir
  | Directory _ -> failwith "a"

let download url =
  try%lwt
    let* resp, body = Cohttp_lwt_unix.Client.get url in
    if Cohttp.Code.is_success @@ Cohttp.Code.code_of_status resp.status then
      Cohttp_lwt.Body.to_string body
    else Lwt.fail Request_error
  with _ -> Lwt.fail Request_error
