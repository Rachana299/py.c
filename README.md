# Py.c

Compiler Design Project — Python-to-**C** translator, using **lex** and **yacc**
(flex/bison).

This is a port of [Py.js](https://github.com/DharunThota/Py.js) (Python → JavaScript)
retargeted to emit compilable C instead.

## What changed vs. the original Py.js

- **Target language**: emits C (`printf`, `int`/`char *` declarations, `void`
  functions) instead of JavaScript (`console.log`, `let`, `function`).
- **Type inference**: C is statically typed, so each variable's C type
  (`int` vs `char *`) is inferred from its first assignment and tracked in
  the symbol table, so later `print(x)` calls know whether to use `%d` or `%s`.
- **Function hoisting**: C can't nest function definitions inside `main()`,
  so every `def` is hoisted above `main()` in the generated file.
- **Function parameters**: since the source language has no type
  annotations, and this subset always calls functions with string
  arguments, parameters are generated as `const char *`.
- **Real indentation handling**: the original project never implemented
  INDENT/DEDENT tracking (it's commented out in the original
  `tokenizer.l`), so blocks in the original just swallowed every following
  statement to the end of the file. This port implements genuine
  Python-style indentation tracking (an indent stack, INDENT/DEDENT
  tokens, mixed tabs/spaces support) so `if`/`while`/`for`/`def` blocks are
  properly and independently scoped — this was necessary for the C output
  to actually compile and run correctly.

## Supported subset

Same subset as the original: `def`, `if`/`else`, `while`,
`for x in range(a, b)`, `print(...)`, assignment, arithmetic
(`+ - * /`), comparisons, and simple function calls.

## Build & run

```sh
make          # builds ./parser
make run      # runs ./parser on test.py, prints token trace + generated C
```

To actually compile and execute the generated C:

```sh
make transpile   # builds parser, transpiles test.py -> output.c, compiles and runs it
```

Or manually:

```sh
./parser < test.py > output.c
gcc output.c -o output
./output
```

## Known limitations (inherited from the design, not bugs)

- No real Python type system — everything is either `int` or `char *`;
  there's no float, list, dict, etc.
- String concatenation with `+` is not supported (arithmetic `+`/`-`
  assume numeric operands).
- Function parameter types are always assumed to be `const char *`.
- No `return` statement codegen (token exists, grammar rule does not).
