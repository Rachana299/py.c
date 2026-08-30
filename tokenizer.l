%option noyywrap
%option prefix="raw_yy"

%x BOL

%{
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// For token storage
#include "parser.tab.h"

void print_token(const char *token, const char *value) {
    printf("<%s, %s>\n", token, value);
}

// --- Indentation tracking (Python-style INDENT/DEDENT) -----------------
#define MAX_INDENT_STACK 128
static int indent_stack[MAX_INDENT_STACK] = {0};
static int indent_top = 0;      // index of the current top of the stack
static int pending_dedents = 0; // extra DEDENTs queued after a multi-level dedent

static int indent_width(const char *s) {
    int w = 0;
    for (; *s; s++) {
        if (*s == '\t') w += 8;
        else w += 1;
    }
    return w;
}
%}

%%

<INITIAL>\n {
    print_token("NEWLINE", "\\n");
    BEGIN(BOL);
    return NEWLINE;
}
<INITIAL>\r { print_token("CARRIAGE RETURN", "\\r"); BEGIN(BOL); return NEWLINE; }

<BOL>^[ \t]*\n {
    /* Blank line: doesn't affect indentation, no token emitted. */
}

<BOL>^[ \t]+ {
    int w = indent_width(yytext);
    BEGIN(INITIAL);
    if (w > indent_stack[indent_top]) {
        indent_stack[++indent_top] = w;
        print_token("INDENT", yytext);
        return INDENT;
    } else if (w < indent_stack[indent_top]) {
        int levels = 0;
        while (indent_top > 0 && indent_stack[indent_top] > w) {
            indent_top--;
            levels++;
        }
        pending_dedents = levels - 1;
        print_token("DEDENT", "");
        return DEDENT;
    }
    /* same indentation level: no token, fall through to scan the rest of the line */
}

<BOL>. {
    /* A line with NO leading whitespace at all (width 0). Flex can't match
       a purely-empty pattern, so instead we match one real character,
       push it back unconsumed with yyless(0), and treat width as 0. */
    yyless(0);
    BEGIN(INITIAL);
    int w = 0;
    if (w < indent_stack[indent_top]) {
        int levels = 0;
        while (indent_top > 0 && indent_stack[indent_top] > w) {
            indent_top--;
            levels++;
        }
        pending_dedents = levels - 1;
        print_token("DEDENT", "");
        return DEDENT;
    }
    /* already at width 0: no token, fall through to scan the rest of the line */
}

<INITIAL,BOL><<EOF>> {
    if (indent_top > 0) {
        indent_top--;
        print_token("DEDENT", "");
        return DEDENT;
    }
    yyterminate();
}

"def"           { print_token("KEYWORD", "def"); return DEF; }
"if"            { print_token("KEYWORD", "if"); return IF; }
"else"          { print_token("KEYWORD", "else"); return ELSE; }
"while"         { print_token("KEYWORD", "while"); return WHILE; }
"for"           { print_token("KEYWORD", "for"); return FOR; }
"in"            { print_token("KEYWORD", "in"); return IN; }
"range"         { print_token("KEYWORD", "range"); return RANGE; }
"return"        { print_token("KEYWORD", "return"); return RETURN; }
"break"         { print_token("KEYWORD", "break"); return BREAK; }
"continue"      { print_token("KEYWORD", "continue"); return CONTINUE; }
"print"         { print_token("KEYWORD", "print"); return PRINT; }

[a-zA-Z_][a-zA-Z0-9_]* {
    print_token("VARIABLE", yytext);
    yylval.str = strdup(yytext);
    return VARIABLE;
}

[0-9]+ {
    print_token("NUMBER", yytext);
    yylval.str = strdup(yytext);
    return NUMBER;
}

\"[^\"]*\" {
    print_token("STRING", yytext);
    yylval.str = strdup(yytext);
    return STRING;
}

"=="            { print_token("OPERATOR", "=="); return EQUALS; }
"="             { print_token("OPERATOR", "="); return ASSIGN; }
"!="            { print_token("OPERATOR", "!="); return NOT_EQUALS; }
"<"             { print_token("OPERATOR", "<"); return LESS_THAN; }
"<="            { print_token("OPERATOR", "<="); return LESS_EQUAL; }
">"             { print_token("OPERATOR", ">"); return GREATER_THAN; }
">="            { print_token("OPERATOR", ">="); return GREATER_EQUAL; }
"+"             { print_token("OPERATOR", "+"); return PLUS; }
"-"             { print_token("OPERATOR", "-"); return MINUS; }
"*"             { print_token("OPERATOR", "*"); return MULT; }
"/"             { print_token("OPERATOR", "/"); return DIVIDE; }

"("             { print_token("DELIMITER", "("); return LPAREN; }
")"             { print_token("DELIMITER", ")"); return RPAREN; }
"{"             { print_token("DELIMITER", "{"); return LBRACE; }
"}"             { print_token("DELIMITER", "}"); return RBRACE; }
":"             { print_token("DELIMITER", ":"); return COLON; }
","             { print_token("DELIMITER", ","); return COMMA; }

[ ]             { print_token("SPACE", " "); }

[\t]+           { /* stray mid-line tabs: ignore */ }

"#"[^\n]*       { /* Ignore comments */ }

.               { printf("Unrecognized character: %s\n", yytext); }
%%

// Public scanner entry point used by the parser. Wraps the flex-generated
// raw_yylex() (see %option prefix) to first drain any queued DEDENT tokens
// produced when a line dedents by more than one indentation level at once.
#undef yylex
int yylex(void) {
    static int initialized = 0;
    if (!initialized) {
        initialized = 1;
        BEGIN(BOL);
    }
    if (pending_dedents > 0) {
        pending_dedents--;
        print_token("DEDENT", "");
        return DEDENT;
    }
    return raw_yylex();
}
