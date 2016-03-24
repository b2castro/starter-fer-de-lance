open Printf
open Expr
open Instruction
open ExtLib

type 'a envt = (string * 'a) list

let count = ref 0
let gen_temp base =
  count := !count + 1;
  sprintf "temp_%s_%d" base !count

type hole =
  | CHole of (cexpr -> aexpr)
  | ImmHole of (immexpr -> aexpr)

let fill_imm (h : hole) (v : immexpr) : aexpr =
  match h with
    | CHole(k) -> (k (CImmExpr(v)))
    | ImmHole(k) -> (k v)

let fill_c (h : hole) (c : cexpr) : aexpr =
  match h with
    | CHole(k) -> (k c)
    | ImmHole(k) ->
      let tmp = gen_temp "" in
      ALet(tmp, c, k (ImmId(tmp)))

let return_hole = CHole(fun ce -> ACExpr(ce))

let rec anf_list (es : expr list) (k : immexpr list -> aexpr) : aexpr =
  match es with
    | [] -> k []
    | e::rest ->
      anf e (ImmHole(fun imm ->
        anf_list rest (fun imms -> k (imm::imms))))

and anf (e : expr) (h : hole) : aexpr =
  match e with
    | ENumber(n) -> fill_imm h (ImmNumber(n)) 
    | EBool(b) -> fill_imm h (ImmBool(b)) 
    | ELambda(ids, body) ->
      (* FILL: You do this case *)
      failwith "ELambda not yet implemented for ANF"
    | EId(x) -> fill_imm h (ImmId(x))
    | EPrim1(op, e) ->
      anf e (ImmHole(fun imm -> (fill_c h (CPrim1(op, imm)))))
    | EPrim2(op, left, right) ->
      anf left (ImmHole(fun limm ->
        anf right (ImmHole(fun rimm ->
          (fill_c h (CPrim2(op, limm, rimm)))))))
    | EApp(f, args) ->
      anf f (ImmHole(fun fimm ->
        anf_list args (fun aimms -> fill_c h (CApp(fimm, aimms)))))
    | EPair(left, right) -> 
      anf left (ImmHole(fun limm ->
        anf right (ImmHole(fun rimm ->
          (fill_c h (CPair(limm, rimm)))))))
    | EIf(cond, thn, els) ->
      anf cond (ImmHole(fun cimm ->
        (fill_c h (CIf(cimm, (anf thn return_hole), (anf els return_hole))))))
    | ELet([], body) -> anf body h
    | ELet((name, value)::rest, body) ->
      anf value (CHole(fun ce ->
        ALet(name, ce, anf (ELet(rest, body)) h)))

let rec find ls x =
  match ls with
    | [] -> None
    | (y,v)::rest ->
      if y = x then Some(v) else find rest x

let const_true = HexConst(0xffffffff)
let const_false = HexConst(0x7fffffff)

let acompile_imm_arg (i : immexpr) _ (env : int envt) : arg =
  match i with
    | ImmNumber(n) ->
      Const((n lsl 1))
    | ImmBool(b) ->
      if b then const_true else const_false
    | ImmId(name) ->
      begin match find env name with
        | Some(stackloc) -> RegOffset(-4 * stackloc, EBP)
        | None -> failwith ("Unbound identifier in compile: " ^ name)
      end

let acompile_imm (i : immexpr) (si : int) (env : int envt) : instruction list =
  [ IMov(Reg(EAX), acompile_imm_arg i si env) ]

let max n m = if n > m then n else m
let rec count_c_vars (ce : cexpr) : int =
  match ce with
    | CIf(_, thn, els) ->
      max (count_vars thn) (count_vars els)
    | _ -> 0

and count_vars (ae : aexpr) : int =
  match ae with
    | ALet(x, bind, body) -> 
      1 + (max (count_c_vars bind) (count_vars body))
    | ACExpr(ce) -> count_c_vars ce

let rec contains x ids =
  match ids with
    | [] -> false
    | elt::xs -> (x = elt) || (contains x xs)

let add_set x ids =
  if contains x ids then ids
  else x::ids

and freevars e =
  (* TODO: fill in freevars *)
  []

let rec acompile_step (s : cexpr) (si : int) (env : int envt) : instruction list =
  []
  (* TODO: fill this in (use code from old assignments if you like) *)

and acompile_expr (e : aexpr) (si : int) (env : int envt) : instruction list =
  []

let rec find_one (l : 'a list) (elt : 'a) : bool =
  match l with
    | [] -> false
    | x::xs -> (elt = x) || (find_one xs elt)

let rec find_dup (l : 'a list) : 'a option =
  match l with
    | [] -> None
    | [x] -> None
    | x::xs ->
      if find_one xs x then Some(x) else find_dup xs

let rec well_formed_e (e : expr) (env : bool envt) =
  []

let compile_to_string (prog : expr) =
  match well_formed_e prog [] with
    | x::rest ->
      let errstr = (List.fold_left (fun x y -> x ^ "\n" ^ y) "" (x::rest)) in
      failwith errstr
    | [] ->
      let anfed = (anf prog return_hole) in
      count := 0;
      let compiled_main = (acompile_expr anfed 1 []) in
      let varcount = count_vars anfed in
      let stackjump = 4 * varcount in
      let prelude = "
section .text
extern print
global our_code_starts_here" in
          let main_start = [
            ILabel("our_code_starts_here");
            (* heap start *)
            IMov(Reg(ESI), RegOffset(4, ESP));
            IAdd(Reg(ESI), Const(8));
            IAnd(Reg(ESI), HexConst(0xFFFFFFF8));
            IPush(Reg(EBP));
            IMov(Reg(EBP), Reg(ESP));
            ISub(Reg(ESP), Const(stackjump))
          ] in
          let postlude = [
            IMov(Reg(ESP), Reg(EBP));
            IPop(Reg(EBP));
            IRet;
          ] in
          let as_assembly_string = (to_asm (
            main_start @
            compiled_main @
            postlude)) in
          sprintf "%s%s\n" prelude as_assembly_string

