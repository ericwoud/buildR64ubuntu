CC      = gcc
CCX     = arm-linux-gnueabihf-gcc
RM      = rm -f

default: all

all: echo-bpir64-mbr

echo-bpir64-mbr: echo-bpir64-mbr.c
	$(CC) -o echo-bpir64-mbr echo-bpir64-mbr.c

clean veryclean:
	$(RM) echo-bpir64-mbr
