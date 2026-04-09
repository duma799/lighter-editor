LUA_INC = /opt/homebrew/Cellar/lua@5.4/5.4.8/include/lua5.4
CC      = clang
SRC     = fspicker.m
OUT     = fspicker.dylib

CFLAGS  = -O2 -Wall -shared -fPIC \
          -undefined dynamic_lookup \
          -fobjc-arc \
          -I$(LUA_INC)

LDFLAGS = -framework AppKit \
          -framework Foundation

.PHONY: all clean

all: $(OUT)
	@echo "Built $(OUT)"

$(OUT): $(SRC)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm -f $(OUT)
