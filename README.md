# Fer-de-lance

![A fer-de-lance](https://upload.wikimedia.org/wikipedia/commons/5/51/Bothrops_asper_-_Tortuguero1.jpg)

Fer-de-lance, aka FDL, aka **F**unctions **D**efined by **L**ambdas, is an
egg-eater-like language with anonymous, first-class functions.

## Language

### Syntax

Fer-de-lance starts with the pairs compiler (not full tuples, just pairs) and
has two significant syntactic changes.  First, it _removes_ the notion of
function declarations as a separate step in the beginning of the program.
Second, it _adds_ the notion of a `lambda` expression for defining anonymous
functions, and allows expressions rather than just strings in function position:

```
type program = expr

type expr =
    ...
  | ELambda of string list * expr
  | EApp of expr * expr list


type cexpr =
    ...
  | CLambda of string list * aexpr
  | CApp of immexpr * immexpr list
```

Parentheses are required around lambda expressions in FDL:

```
expr :=
    ...
  | (lambda <ids> : <expr>)
  | (lambda: <expr>)

ids :=
  | <id> , <ids>
  | <id>
```

### Semantics

Functions should behave just as if they followed a substitution-based
semantics.  This means that when a function is constructed, the program should
store any variables that they reference that aren't part of the argument list,
for use when the function is called.  This naturally matches the semantics of
function values in languages like OCaml and Python.

There are several updates to errors as a result of adding first-class functions:

- There is no longer a well-formedness error for an arity mismatch.  It is a
  runtime error.
- The value in function position may not be a function (for example, a user may
  erroneously apply a number), which should raise a (dynamic) error that
  reports "non-function"
- There should still be a (well-formedness) check for duplicate argument names,
  but there is no longer a check for duplicate function declarations

## Implementation

### Memory Layout and Function Values

Functions are stored in memory with the following layout: 


```
-----------------------------------------------------------------
| arity | code ptr | var1 | var2 | ... | varn | (maybe padding) |
-----------------------------------------------------------------
```

For example, in this program:

```
let x = 10 in
let y = 12 in
let f = (lambda z: x + y + z) in
f(5)
```

The memory layout of the `lambda` would be:

```
----------------------------------------------
|   1  | <address> |  20  |  24  | <padding> |
----------------------------------------------
```

There is one argument (`z`), so `1` is stored for arity.  There are two free
variables—`x` and `y`—so the corresponding values are stored in contiguous
addresses (`20` to represent 10 and `24` to represent 12).  (If the function
stored three variables instead of two, then padding would be needed).

Function _values_ are stored in variables and registers as the address
of the first word in the function's memory, but with an additional `5`
(`101` in binary) added to the value to act as a tag.

The value layout is now:

```
0xWWWWWWW[www0] - Number
0xFFFFFFF[1111] - True
0x7FFFFFF[1111] - False
0xWWWWWWW[w001] - Pair
0xWWWWWWW[w101] - Function
```

### Computing and Storing Free Variables

An important part of saving function values is figuring out the set of
variables that need to be stored, and storing them on the heap.  Our compiler
needs to generated code to store all of the _free_ variables in a function –
all the variables that are used but not defined by an argument or let binding
inside the function.  So, for example, `x` is free and `y` is not in:

```
(lambda(y): x + y)
```

In this next expression, `z` is free, but `x` and `y` are not, because `x` is
bound by the `let` expression.

```
(lambda(y): let x = 10 in x + y + z)
```

Note that if these examples were the whole program, well-formedness would
signal an error that these variables are unbound.  However, these expressions
could appear as sub-expressions in other programs, for example:

```
let x = 10 in
let f = (lambda(y): x + y) in
f(10)
```

In this program, `x` is not unbound – it has a binding in the first branch of
the `let`.  However, relative to the `lambda` expression, it is _free_, since
there is no binding for it within the `lambda`’s arguments or body.

You will write a function `freevars` that takes an `aexpr` and returns the set
of free variables (as a list):

```
let freevars (ae : aexpr) : (string list) = 
  ...
```

You may need to write one or more helper functions for `freevars`, that keep
track of an environment.  Then `freevars` can be used when compiling `CLambda`
to fetch the values from the surrounding environment, and store them on the
heap.  In the example of heap layout above, the `freevars` function should
return `["x", "y"]`, and that information can be used in conjunction with `env`
to perform the necessary `mov` instructions.

This means that the generated code for a `lambda` will look much like it did
[in
class](https://github.swarthmore.edu/jpolitz1/cs75-s16-lectures/tree/master/09.2-mar-24),
but with an extra step to move the stored variables:

```
  jmp after1
temp_closure_1:
  <code for body of closure> 
after1:
  mov [esi], <arity>
  mov [esi + 4], temp_closure_1
  mov [esi + 8], <var1>
  ... and so on for each variable to store
  mov eax, esi
  add eax, 5
  add esi, <heap offset amount>
```

### Restoring Saved Variables

The description above outlines how to _store_ the free variables of a function.
They also need to be _restored_ when the function is called, so that each time
the function is called, they can be accessed.

In this assignment we'll treat the stored variables as if they were a special
kind of _local variable_, and reallocate space for them on the stack at the
beginning of each function call.  So each function body will have an additional
part of the prelude that restores the variables onto the stack, and their uses
will be compiled just as local variables are.  This lets us re-use much of our
infrastructure of stack offsets and the environment.

The outline of work here is:

- At the top of the function, get a reference to the address at which the
  function's stored variables are in memory
- Add instructions to the prelude of each function that restore the stored
  variables onto the stack, given this address
- Assuming this stack layout, compile the function's body in an environment
  that will look up all variables, whether stored, arguments, or let-bound, in
  the correct location

The second and third points are straightforward applications of ideas we've
seen already – copying appropriate values from the heap into the stack, and
using the environment to make variable references look at the right locations
on the stack.

The first point requires a little more design work.  If we try to fill in the
body of `temp_closure_1` above, we immediately run into the issue of where we
should find the stored values in memory.  We'd like some way to, say, move the
address of the function value into `eax` so we could start copying values onto
the stack:

```
temp_closure_1:
  <usual prelude>
  mov eax, <function value?>

  mov ecx, [eax + 3]
  mov [ebp - 8], ecx
  mov ecx, [eax + 7]
  mov [ebp - 12], ecx
  ... and so on ...
```

But how do we get access to the function value?  The list of instructions for
`temp_closure_1` may be run for many different instantiations of the function,
so they can't all look in the same place.

To solve this, we are going to augment the _calling convention_ in Fer-de-lance
to pass along the function value when calling a function.  That is, we will
`push` one extra time after pushing all the arguments, and add on the function
value itself from the caller.  So, for example, in call like:

```
f(4, 5)
```

We would generate code for the caller like:

```
mov eax, [ebp-4] ;; (or wherever the variable f happens to be)
<code to check that eax is tagged 101, and has arity 2>
push 8
push 10
push eax
mov eax, [eax - 1] ;; the address of the code pointer for the function value
call eax         ;; call the function
add esp, 12        ;; since we pushed two arguments and the function value, adjust esp by 12
```

Now the function value is available on the stack, accessible just as an
argument (e.g. with `[ebp+8]`), so we can use that in the prelude for restoration:


```
temp_closure_1:
  <usual prelude>
  mov eax, [ebp+8]

  mov ecx, [eax + 3]
  mov [ebp - 8], ecx
  mov ecx, [eax + 7]
  mov [ebp - 12], ecx
  ... and so on ...
```

### Recommended TODO List

- Move over code from past labs and/or lecture code to get the basics going.
  There is intentionally less support code this time to put less structure on
  how errors are reported, etc.  Feel free to start with code copied from past
  labs; note that this assignment uses _pairs_ rather than _tuples_ – most of
  the code for pairs was given along with lecture notes.  Note that the initial
  state of the tests will not run even simple programs until you get things
  started.
- Implement ANF for `ELambda`.  Hint – it's quite similar to what needed to be
  done to ANF a declaration.
- Implement the compilation of `CLambda` and `CApp`, ignoring stored variables.
  You'll deal with storing and checking the arity and code pointer, and
  generating and jumping over the instructions for a function.  Test as you go.
- Implement `freevars`, testing as you go.  You can test with the helper
  `tfvs`, which takes a name, an expression string, and a list of identifiers,
  and checks that `freevars` returns the same list of strings (in any order).
- Implement storing and restoring of variables in the compilation of `CLambda`
  and `CApp`


