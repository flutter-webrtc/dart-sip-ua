all: peg grammar

peg:
	docker build -t peg-tool tool

grammar:
	docker run -it --rm -v `pwd`/lib/src:/src --platform linux/amd64 peg-tool