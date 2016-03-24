open Compile
open Runner
open Printf
open OUnit2
open ExtLib

let t name program expected = name>::test_run program name expected;;
let tvg name program expected = name>::test_run_valgrind program name expected;;
let terr name program expected = name>::test_err program name expected;;

let tfvs name program expected = name>::
  (fun _ ->
    let ast = parse_string name program in
    let anfed = anf ast return_hole in
    let vars = freevars anfed in
    let c = Pervasives.compare in
    assert_equal (List.sort ~cmp:c vars) (List.sort ~cmp:c expected) ~printer:dump)
;;

let program = [
  t "fortytwo" "42" "42";
]

let frees = [
  tfvs "fvs1" "(lambda x: x + y)" ["y"];
]

let suite =
"suite">:::
 program @ frees



let () =
  run_test_tt_main suite
;;

