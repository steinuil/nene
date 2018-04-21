open Lwt.Infix


let with_default def = function
  | Some x -> x
  | None -> def


type flags =
  { download_dir : string option
  ; shows_file   : string option
  ; transmission_host : string option
  ; transmission_port : int option }


let usage chan =
  let cmd_name = Sys.argv.(0) in
  let print = output_string chan in
  print "Usage: ";
  print cmd_name;
  print " [-h] [-download-dir <path>] [-shows <path>]\n";
  print (String.make (8 + String.length cmd_name) ' ');
  print "[-transmission-host <host>] [-transmission-port <port>]\n"


let flags =
  let args = List.tl @@ Array.to_list Sys.argv in
  let rec loop flags acc = match flags, acc with
    | [], acc -> acc
    | "-download-dir" :: path :: rest
    , { download_dir = None; _ } ->
        loop rest { acc with download_dir = Some path }
    | "-shows" :: path :: rest
    , { shows_file = None; _ } ->
        loop rest { acc with shows_file = Some path }
    | "-transmission-host" :: host :: rest
    , { transmission_host = None; _ } ->
        loop rest { acc with transmission_host = Some host }
    | "-transmission-port" :: port :: rest
    , { transmission_port = None; _ } ->
        let port = int_of_string port in
        loop rest { acc with transmission_port = Some port }
    | "-h" :: _, _ | "-help" :: _, _ ->
        usage stdout;
        exit 0
    | opt :: _, _ ->
        failwith ("Unrecognized option: " ^ opt) in
  loop args
    { download_dir = None; shows_file = None
    ; transmission_host = None; transmission_port = None }


let home_dir =
  Sys.getenv "HOME"


let nene_dir =
  let config_dir =
    match Sys.getenv_opt "XDG_CONFIG_HOME" with
    | Some dir -> dir
    | None ->
        Filename.concat home_dir ".config" in
  let nene_dir = Filename.concat config_dir "nene" in
  if not @@ Sys.file_exists nene_dir then
    Unix.mkdir nene_dir 0o700;
  nene_dir


let in_config_dir f =
  Filename.concat nene_dir f


let seen_file =
  in_config_dir "seen.scm"


let shows_file = match flags.shows_file with
  | Some f -> f
  | None -> in_config_dir "shows.scm"


let download url =
  let cmd = "curl", [|"nene-fetch"; url|] in
  try%lwt Lwt_process.pread ~timeout:15. ~stderr:`Dev_null ~env:[||] cmd
  with _ -> Lwt.return ""


let session_id_mutex = Lwt_mutex.create ()


let transmission_url =
  let port = with_default 9091 flags.transmission_port in
  let host = with_default "127.0.0.1" flags.transmission_host in
  Uri.make ~scheme:"http" ~port ~host ~path:"/transmission/rpc" ()


let session_id' : Cohttp.Header.t option ref =
  ref None


let session_id () =
  let%lwt () = Lwt_mutex.lock session_id_mutex in
  match !session_id' with
  | Some headers ->
      Lwt_mutex.unlock session_id_mutex;
      Lwt.return headers
  | None ->
      let%lwt (resp, _) = Cohttp_lwt_unix.Client.get transmission_url in
      let headers = Cohttp_lwt.Response.headers resp in
      let header_name = "X-Transmission-Session-Id" in
      let session_id_hdr =
        match Cohttp.Header.get headers header_name with
        | Some id -> Cohttp.Header.init_with header_name id
        | None -> Cohttp.Header.init () in
      session_id' := Some session_id_hdr;
      Lwt_mutex.unlock session_id_mutex;
      Lwt.return session_id_hdr


let resp_success = function
  | ("result", `String "success") -> true
  | _ -> false


let add_torrent url =
  let dl_dir = match flags.download_dir with
    | Some d -> [ "download-dir", `String d ]
    | None -> [] in
  let json = `Assoc
      [ "method", `String "torrent-add"
      ; "arguments", `Assoc
        (("filename", `String url) :: dl_dir) ] in
  let%lwt headers = session_id () in
  let body = Cohttp_lwt.Body.of_string @@ Yojson.to_string json in
  let%lwt (_, body) = Cohttp_lwt_unix.Client.post ~body ~headers transmission_url in
  let%lwt resp = Cohttp_lwt.Body.to_string body in
  match Yojson.Basic.from_string resp with
  | `Assoc assocs ->
      if List.exists resp_success assocs then
        Lwt.return ()
      else
        Lwt.fail (Failure "Couldn't add the torrent to transmission")
  | _ ->
      Lwt.fail (Failure "Couldn't add the torrent to transmission")
