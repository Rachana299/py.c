all: parser

parser: parser.tab.c lex.raw_yy.c
	gcc -std=gnu11 parser.tab.c lex.raw_yy.c -o parser -lfl

lex.raw_yy.c: tokenizer.l parser.tab.h
	flex tokenizer.l

parser.tab.c parser.tab.h: parser.y
	bison -d parser.y

clean:
	rm -f parser lex.raw_yy.c parser.tab.c parser.tab.h output.c output

run: parser
	./parser < test.py

# Transpile test.py to output.c and compile+run the generated C
transpile: parser
	./parser < test.py > output.c
	gcc -std=gnu11 output.c -o output
	./output
