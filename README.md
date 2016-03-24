# Fer-de-lance

Fer-de-lance, aka FDL, aka **F**unctions **D**efined by **L**ambdas, is an
egg-eater-like language with anonymous, first-class functions.

## Language

### Syntax

Fer-de-lance starts with the pairs compiler (not full tuples, just pairs) and
has two significant syntactic changes.  First, it _removes_ the notion of
function declarations as a separate step in the beginning of the program.
Second, it _adds_ the notion of a `lambda` expression for defining anonymous
functions.

```
type program = expr

type expr =
    ...
  | ELambda of string list * expr


type cexpr =
    ...
  | CLambda of string list * aexpr
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

## Implementation

### Memory Layout and Function Values

Functions are stored in memory with the following layout: 


```
-------------------------------------------------------------------------
| arity | code ptr | #vars | var1 | var2 | ... | varn | (maybe padding) |
-------------------------------------------------------------------------
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
------------------------------------------------------
|   1  | <address> |   2   |  20  |  24  | <padding> |
------------------------------------------------------
```

There is one argument (`z`), so `1` is stored for arity.  There are two free
variables—`x` and `y`—so a `2` is stored for the number of variables.  Then
the values are stored in contiguous addresses (`20` to represent 10 and `24` to
represent 12).  Since all of this takes up an odd number (`5`) of words, an
extra word is used for padding to ensure 8-byte alignment.  (If the function
stored three variables instead of two, then the padding wouldn't be needed).


Function _values_ are stored in variables and registers as the addres
of the first word in the function's memory, but with an additional `5`
(`101` in binary) added to the value to act as a tag.

The value layout is now:

```
0xWWWWWWW[www0] - Number
0xFFFFFFF[1111] - True
0x7FFFFFF[1111] - False
0xWWWWWWW[w001] - Tuple
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
let rec freevars (ae : aexpr) : (string list) = 
  ...
```

This can be used when compiling `CLambda` to fetch the values from the
surrounding environment, and store them on the heap.  In the example of heap
layout above, the `freevars` function should return `["x", "y"]`, and that
information can be used in conjunction with `env` to perform the necessary
`mov` instructions.

This means that the generated code for a `lambda` will look like it did [in
class](https://github.swarthmore.edu/jpolitz1/cs75-s16-lectures/tree/master/09.2-mar-24),
but with an extra step to move the stored variables:

```
  jmp after1
temp_closure_1:
  <code for body of closure> 
after1:
  mov [esi], <arity>
  mov [esi + 4], temp_closure_1
  mov [esi + 8], <number of variables>
  mov [esi + 12], <var1>
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











