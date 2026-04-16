LUA_INC = /opt/homebrew/Cellar/lua@5.4/5.4.8/include/lua5.4
CC      = clang

CFLAGS  = -O2 -Wall -shared -fPIC \
          -undefined dynamic_lookup \
          -fobjc-arc

LDFLAGS = -framework AppKit \
          -framework Foundation

TARGETS = fspicker.dylib titlebar.dylib pty.dylib

.PHONY: all clean

all: $(TARGETS)
	@echo "Built: $(TARGETS)"

%.dylib: %.m
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

pty.dylib: pty.c
	$(CC) -O2 -Wall -shared -fPIC -undefined dynamic_lookup -lutil -o $@ $<

clean:
	rm -f $(TARGETS)
