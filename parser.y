%code requires {
// A code fragment together with its inferred C type
// (is_str = 1 -> char*, is_str = 0 -> int)
typedef struct {
    char *code;
    int is_str;
} Val;
}

%{
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define MAX 1024

// Function declarations
void yyerror(const char *s);
int yylex(void);

int current_indent = 0;
int previous_indent = 0;

// Symbol table: tracks each variable's inferred type so later
// references (e.g. inside print()) know whether to use %d or %s.
struct symbol {
    char name[128];
    int scope_id;
    int is_str;
} sym_tbl[MAX];

int sym_count = 0;
int scope_count = 0;

int is_declared(char *name, int scope) {
    for (int i = 0; i < sym_count; i++) {
        if (strcmp(sym_tbl[i].name, name) == 0 && sym_tbl[i].scope_id == scope) {
            return 1;
        }
    }
    return 0;
}

int get_type(char *name, int scope) {
    for (int i = 0; i < sym_count; i++) {
        if (strcmp(sym_tbl[i].name, name) == 0 && sym_tbl[i].scope_id == scope) {
            return sym_tbl[i].is_str;
        }
    }
    return 0; // default to int if unknown
}

void declare(char *name, int scope, int is_str) {
    strcpy(sym_tbl[sym_count].name, name);
    sym_tbl[sym_count].scope_id = scope;
    sym_tbl[sym_count].is_str = is_str;
    sym_count++;
}

// C can't nest function definitions inside main(), so every
// function_definition is hoisted here and printed above main().
char func_defs[8192] = "";

// Python function params carry no type annotation. Since every
// function in the supported subset is called with string literals
// (see function_call), parameters are generated as `const char *`.
char *typed_params(const char *params) {
    char *result = malloc(1024);
    result[0] = '\0';
    if (params == NULL || strlen(params) == 0) {
        return result;
    }
    char *copy = strdup(params);
    char *token = strtok(copy, ",");
    int first = 1;
    while (token != NULL) {
        while (*token == ' ') token++;
        if (!first) strcat(result, ", ");
        strcat(result, "const char *");
        strcat(result, token);
        first = 0;
        token = strtok(NULL, ",");
    }
    free(copy);
    return result;
}

%}

%union {
    char *str;
    Val val;
}

%token <str> VARIABLE
%token <str> DEF IF ELSE WHILE FOR RETURN BREAK CONTINUE PRINT IN RANGE
%token <str> STRING
%token <str> NUMBER
%token EQUALS ASSIGN NOT_EQUALS LESS_THAN LESS_EQUAL GREATER_THAN GREATER_EQUAL
%left PLUS MINUS MULT DIVIDE
%token LPAREN RPAREN LBRACE RBRACE COLON COMMA
%token NEWLINE INDENT DEDENT
%type <val> expression term
%type <str> program statements block statement print_statement assignment if_statement for_statement while_statement relop function_definition parameter_list function_call

%%

program:
    statements
    {
        printf("#include <stdio.h>\n#include <string.h>\n\n");
        if (strlen(func_defs) > 0) {
            printf("%s\n", func_defs);
        }
        printf("int main() {\n%s\n    return 0;\n}\n", $1);
    }
    ;

statements:
    statement statements
    {
        char *buffer = malloc(strlen($1) + strlen($2) + 2);
        sprintf(buffer, "%s\n%s", $1, $2);
        $$ = buffer;
    }
    |
    statement
    {
        $$ = $1;
    }
    ;

// A block is a properly indented group of statements, delimited by real
// INDENT/DEDENT tokens from the lexer (Python-style indentation), rather
// than letting `statements` greedily swallow everything to end of file.
block:
    INDENT statements DEDENT
    {
        $$ = $2;
    }
    ;

statement:
    print_statement NEWLINE
    {
        $$ = $1;
    }
    | assignment NEWLINE
    {
        $$ = $1;
    }
    | function_call NEWLINE
    {
        $$ = $1;
    }
    | if_statement
    | for_statement
    | while_statement
    | function_definition
    ;

print_statement:
    PRINT LPAREN expression RPAREN
    {
        char *buffer = malloc(strlen($3.code) + 32);
        if ($3.is_str) {
            sprintf(buffer, "printf(\"%%s\\n\", %s);", $3.code);
        } else {
            sprintf(buffer, "printf(\"%%d\\n\", %s);", $3.code);
        }
        $$ = buffer;
    }
    ;

assignment:
    VARIABLE ASSIGN expression
    {
        char *buffer = malloc(strlen($1) + strlen($3.code) + 20);
        if (is_declared($1, 0) == 0) {
            declare($1, 0, $3.is_str);
            if ($3.is_str) {
                sprintf(buffer, "char *%s = %s;", $1, $3.code);
            } else {
                sprintf(buffer, "int %s = %s;", $1, $3.code);
            }
        } else {
            sprintf(buffer, "%s = %s;", $1, $3.code);
        }
        $$ = buffer;
    }
    ;

if_statement:
    IF expression COLON NEWLINE block
    {
        char *buffer = malloc(strlen($2.code) + strlen($5) + 16);
        sprintf(buffer, "if (%s) {\n%s\n}\n", $2.code, $5);
        $$ = buffer;
    }
    | IF expression COLON NEWLINE block ELSE COLON NEWLINE block
    {
        char *buffer = malloc(strlen($2.code) + strlen($5) + strlen($9) + 32);
        sprintf(buffer, "if (%s) {\n%s}\nelse {\n%s}", $2.code, $5, $9);
        $$ = buffer;
    }
    ;

for_statement:
    FOR VARIABLE IN RANGE LPAREN NUMBER COMMA NUMBER RPAREN COLON NEWLINE block
    {
        char *buffer = malloc(strlen($2) + strlen($6) + strlen($8) + strlen($12) + 32);
        sprintf(buffer, "for (int %s = %s; %s < %s; %s++) {\n%s\n}\n", $2, $6, $2, $8, $2, $12);
        $$ = buffer;
    }
    ;

while_statement:
    WHILE expression COLON NEWLINE block
    {
        char *buffer = malloc(strlen($2.code) + strlen($5) + 16);
        sprintf(buffer, "while (%s) {\n%s\n}\n", $2.code, $5);
        $$ = buffer;
    }
    ;

function_definition:
    DEF VARIABLE LPAREN parameter_list RPAREN COLON NEWLINE block
    {
        char *typed = typed_params($4);
        char *buf = malloc(strlen($2) + strlen(typed) + strlen($8) + 32);
        sprintf(buf, "void %s(%s) {\n%s}\n\n", $2, typed, $8);
        strcat(func_defs, buf);
        free(typed);
        free(buf);
        $$ = strdup(""); // hoisted above main(), nothing inline
    }
    ;

function_call:
    VARIABLE LPAREN parameter_list RPAREN
    {
        char *buffer = malloc(strlen($1) + strlen($3) + 4);
        sprintf(buffer, "%s(%s);", $1, $3);
        $$ = buffer;
    }
    ;

parameter_list:
    /* empty */
    {
        $$ = "";
    }
    | term
    {
        $$ = strdup($1.code);
    }
    | parameter_list COMMA VARIABLE
    {
        $$ = malloc(strlen($1) + strlen($3) + 2);
        sprintf($$, "%s, %s", $1, $3);
    }
    ;

expression:
    expression PLUS term
    {
        char *buf = malloc(strlen($1.code) + strlen($3.code) + 4);
        sprintf(buf, "%s + %s", $1.code, $3.code);
        $$.code = buf;
        $$.is_str = 0;
    }
    | expression MINUS term
    {
        char *buf = malloc(strlen($1.code) + strlen($3.code) + 4);
        sprintf(buf, "%s - %s", $1.code, $3.code);
        $$.code = buf;
        $$.is_str = 0;
    }
    | expression relop expression
    {
        char *buf = malloc(strlen($1.code) + strlen($2) + strlen($3.code) + 4);
        sprintf(buf, "%s %s %s", $1.code, $2, $3.code);
        $$.code = buf;
        $$.is_str = 0;
    }
    | term
    {
        $$ = $1;
    }
    ;

relop:
    EQUALS { $$ = "=="; }
    | NOT_EQUALS { $$ = "!="; }
    | LESS_THAN { $$ = "<"; }
    | LESS_EQUAL { $$ = "<="; }
    | GREATER_THAN { $$ = ">"; }
    | GREATER_EQUAL { $$ = ">="; }
    ;

term:
    term MULT term
    {
        char *buf = malloc(strlen($1.code) + strlen($3.code) + 4);
        sprintf(buf, "%s * %s", $1.code, $3.code);
        $$.code = buf;
        $$.is_str = 0;
    }
    | term DIVIDE term
    {
        char *buf = malloc(strlen($1.code) + strlen($3.code) + 4);
        sprintf(buf, "%s / %s", $1.code, $3.code);
        $$.code = buf;
        $$.is_str = 0;
    }
    | NUMBER
    {
        $$.code = strdup($1);
        $$.is_str = 0;
    }
    | LPAREN expression RPAREN
    {
        char *buf = malloc(strlen($2.code) + 3);
        sprintf(buf, "(%s)", $2.code);
        $$.code = buf;
        $$.is_str = $2.is_str;
    }
    | VARIABLE
    {
        $$.code = strdup($1);
        $$.is_str = get_type($1, 0);
    }
    | STRING
    {
        $$.code = strdup($1);
        $$.is_str = 1;
    }
    ;

%%

void yyerror(const char *s) {
    fprintf(stderr, "Error: %s\n", s);
}

int main() {
    return yyparse();
}
