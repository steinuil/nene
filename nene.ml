open Nene_lib

let ( let* ) = Result.bind
let ( let+ ) = Option.bind
let option_or d = function Some _ as s -> s | None -> d

let default_seen_file =
  let ( / ) = Filename.concat in
  let+ xdg_state_home =
    match Sys.getenv_opt "XDG_STATE_HOME" with
    | Some dir -> Some dir
    | None ->
        Sys.getenv_opt "HOME" |> Option.map (fun h -> h / ".local" / "state")
  in
  Some (xdg_state_home / "nene" / "shows.scm")

let rec mkdir_p ?(permissions = 0o755) dir =
  if Sys.file_exists (Filename.dirname dir) then Sys.mkdir dir permissions
  else mkdir_p (Filename.dirname dir) ~permissions

let nene config_file seen_file jobs =
  let* () =
    if jobs > 0 then Ok ()
    else Error (`Msg "Specify a number of jobs higher than 0.")
  in
  let* seen_file =
    seen_file
    |> option_or default_seen_file
    |> Option.to_result
         ~none:
           (`Msg
             "Coulnd't determine the config dir, you should explicitly specify \
              the seen file with the --seen option.")
  in
  let seen = Seen.read_file seen_file in
  let* Config.{ backend; trackers } =
    Config.File.parse_file config_file
    |> Option.to_result
         ~none:(`Msg "An error occurred while reading the config file.")
  in
  let backend = Backend.from_cfg backend in
  let seen = Lwt_main.run (Core.run ~seen ~jobs ~backend ~trackers) in
  if not (Sys.file_exists (Filename.dirname seen_file)) then
    mkdir_p (Filename.dirname seen_file);
  Seen.write_file seen_file seen;
  Ok ()

open Cmdliner

let config_file =
  let doc = "Path to the config file." in
  Arg.(required & pos 0 (some file) None & info [] ~docv:"CONFIG" ~doc)

let seen_file =
  let doc =
    "Path to the file in which to store the already downloaded episodes."
  in
  Arg.(value & opt (some string) None & info [ "seen" ] ~docv:"FILE" ~doc)

let jobs = Arg.(value & opt int 4 & info [ "j"; "jobs" ] ~docv:"COUNT")
let nene_t = Term.(term_result (const nene $ config_file $ seen_file $ jobs))
let () = Cmd.eval (Cmd.v (Cmd.info "nene") nene_t) |> Stdlib.exit
