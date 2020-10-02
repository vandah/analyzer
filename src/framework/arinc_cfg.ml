(** ARINC Control-flow graph implementation. *)

module GU = Goblintutil
module CF = Cilfacade
open Cil
open Deriving.Cil
include Arinc_node

type edgeAct =
  | StartComputation of int
  (** Computation that takes a certain WCET *)
  | FinishComputation
  | ResumeTask of int
  (** Resume another task *)
  | SuspendTask of int
  (** Suspend another task *)
  | TimedWait of int
  | SetEvent of int
  | WaitEvent of int
  | ResetEvent of int
  | WaitSemaphore of int
  | SignalSemaphore of int
  | PeriodicWait
  | WaitingForPeriod
  | WaitingForEndWait of int
  | NOP
  [@@deriving yojson]

type edge = int * edgeAct

type arinc_cfg = arinc_node -> ((location * edge) list * arinc_node) list

type task_node = PCSingle of int [@@deriving yojson]
type task_edge = edgeAct [@@deriving yojson]
(* with the assumption that very node appears in the list of task_node tuples exactly once *)
type arinc_task_cfg = int * (task_node * (task_edge list * task_node) list) list [@@deriving yojson]


let minimal_task_0:arinc_task_cfg = (0,
  [
    (PCSingle 0,[([TimedWait 20], PCSingle 1)]);
    (PCSingle 1,[([WaitingForEndWait 20], PCSingle 2)]);
    (PCSingle 2,[([PeriodicWait], PCSingle 3)]);
    (PCSingle 3,[([WaitingForPeriod], PCSingle 0)]);
  ])

let minimal_task_1:arinc_task_cfg = (1,
  [
    (PCSingle 0,[([StartComputation 40], PCSingle 1)]);
    (PCSingle 1,[([FinishComputation], PCSingle 2)]);
    (PCSingle 2,[([NOP], PCSingle 0)]);
  ])

module type CfgBackward =
sig
  val prev : arinc_node -> ((location * edge) list * arinc_node) list
end

module type CfgForward =
sig
  val next : arinc_node -> ((location * edge) list * arinc_node) list
end

module type CfgBidir =
sig
  include CfgBackward
  include CfgForward
end

module H = BatHashtbl.Make(Arinc_Node)

(* Dumps a statement to the standard output *)
let pstmt stmt = dumpStmt defaultCilPrinter stdout 0 stmt; print_newline ()

let current_node : arinc_node option ref = ref None


(* Utility function to add stmt edges to the cfg *)
let mkEdge cfgF cfgB fromNode edge toNode =
  let addCfg t (e,f)=
    let addCfg' t xs f =
      H.add cfgB t (xs,f);
      H.add cfgF f (xs,t);
      Messages.trace "cfg" "done\n\n"
    in
    addCfg' t [Cil.locUnknown ,e] f
  in
  addCfg  toNode (edge, fromNode); ()

let example_extracted () =
  let cfgF = H.create 113 in
  let cfgB = H.create 113 in
  let mkEdge = mkEdge cfgF cfgB in

  for i = 0 to 7 do
    mkEdge (PC ([0; i])) (0, StartComputation 10) (PC [13; i]);
    mkEdge (PC ([13; i])) (0, FinishComputation) (PC [1; i]);

    mkEdge (PC ([1; i])) (0, PeriodicWait) (PC [2; i]);
    mkEdge (PC ([2; i])) (0, WaitingForPeriod) (PC [3; i]);
    mkEdge (PC ([3; i])) (0, SetEvent 0) (PC [4; i]);

    mkEdge (PC ([4; i])) (0, StartComputation 20) (PC [14; i]);
    mkEdge (PC ([14; i])) (0, FinishComputation) (PC [5; i]);

    mkEdge (PC ([5; i])) (0, ResumeTask 1) (PC [6; i]);
    mkEdge (PC ([6; i])) (0, TimedWait 20) (PC[12;i]);
    mkEdge (PC ([12; i])) (0, WaitingForEndWait 20) (PC[16;i]);
    mkEdge (PC ([6; i])) (0, WaitEvent 1) (PC [7; i]);
    mkEdge (PC ([7; i])) (0, ResetEvent 1) (PC [8; i]);

    mkEdge (PC ([16; i])) (0, NOP) (PC[9;i]);

    mkEdge (PC ([8; i])) (0, StartComputation 42) (PC [15; i]);
    mkEdge (PC ([15; i])) (0, FinishComputation) (PC [9; i]);

    mkEdge (PC ([9; i])) (0, SuspendTask 1) (PC [10; i]);
    mkEdge (PC ([10; i])) (0, PeriodicWait) (PC [11; i]);
    mkEdge (PC ([11; i])) (0, WaitingForPeriod) (PC [4; i]);

  done;
  for i = 0 to 17 do
    mkEdge (PC ([i; 0])) (1, SuspendTask 1) (PC [i; 1]);
    mkEdge (PC ([i; 1])) (1, WaitSemaphore 0) (PC [i; 2]);

    mkEdge (PC ([i; 2])) (1, StartComputation 40) (PC [i; 6]);
    mkEdge (PC ([i; 6])) (1, FinishComputation) (PC [i; 3]);

    mkEdge (PC ([i; 3])) (1, SignalSemaphore 0) (PC [i; 4]);
    mkEdge (PC ([i; 4])) (1, SetEvent 1) (PC [i; 5]);
    mkEdge (PC ([i; 5])) (1, NOP) (PC [i; 1]);
  done;
  (* Printf.printf "!!!!!!!Edge count %i\n" (List.length (H.find_all cfgB (PC ([9; 4])))); *)
  (* H.iter (fun n (e,t) -> match n,t with PC [a;b], PC[c;d] -> Printf.printf "[%i,%i] -> [%i,%i]\n" a b c d;) cfgF; *)
  H.find_all cfgF, H.find_all cfgB

let minimal_problematic () =
  let cfgF = H.create 113 in
  let cfgB = H.create 113 in
  let mkEdge = mkEdge cfgF cfgB in

  for i = 0 to 2 do
    mkEdge (PC ([0; i])) (0, TimedWait 20) (PC[1;i]);
    mkEdge (PC ([1; i])) (0, WaitingForEndWait 20) (PC[2;i]);
    mkEdge (PC ([2; i])) (0, PeriodicWait) (PC [3; i]);
    mkEdge (PC ([3; i])) (0, WaitingForPeriod) (PC [0; i]);

  done;
  for i = 0 to 3 do
    mkEdge (PC ([i; 0])) (1, StartComputation 40) (PC [i; 1]);
    mkEdge (PC ([i; 1])) (1, FinishComputation) (PC [i; 2]);
    mkEdge (PC ([i; 2])) (1, NOP) (PC [i; 0]);
  done;
  (* Printf.printf "!!!!!!!Edge count %i\n" (List.length (H.find_all cfgB (PC ([9; 4])))); *)
  (* H.iter (fun n (e,t) -> match n,t with PC [a;b], PC[c;d] -> Printf.printf "[%i,%i] -> [%i,%i]\n" a b c d;) cfgF; *)
  H.find_all cfgF, H.find_all cfgB

let create_from (a:arinc_task_cfg) (b:arinc_task_cfg) =
  let cfgF = H.create 113 in
  let cfgB = H.create 113 in
  let mkEdge = mkEdge cfgF cfgB in
  let (id0, edges0) = a in
  let (id1, edges1) = b in
  let nodeCount0 = List.length edges0 in
  let nodeCount1 = List.length edges1 in
  for i = 0 to nodeCount1 -1 do
    List.iter (function (PCSingle from_node, edges_to_node) ->
      List.iter (function (edges, PCSingle to_node) ->
        List.iter (function edge ->
          mkEdge (PC [from_node; i]) (0,edge) (PC [to_node; i])
        ) edges
      ) edges_to_node
    ) edges0
  done;
  for i = 0 to nodeCount0 -0 do
    List.iter (function (PCSingle from_node, edges_to_node) ->
      List.iter (function (edges, PCSingle to_node) ->
        List.iter (function edge ->
          mkEdge (PC [i; from_node]) (1,edge) (PC [i; to_node])
        ) edges
      ) edges_to_node
    ) edges1
  done;
  H.find_all cfgF, H.find_all cfgB

let get_cfg i =
  match i with
  | 0 -> example_extracted ()
  | 1 -> create_from minimal_task_0 minimal_task_1 (* minimal_problematic () *)
  | _ -> failwith ("Selected unknown CFG " ^ string_of_int(i))
