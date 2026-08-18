# Regenerates the protocol bindings and builds the probe. The XML is vendored
# (MIT, Purism SPC) because wlr-protocols is not installed on every machine
# that would want to run this.

PROTO := wlr-output-power-management-unstable-v1
CFLAGS += -Wall -Wextra
WL := $(shell pkg-config --cflags --libs wayland-client)

probe: probe.c $(PROTO)-protocol.c $(PROTO)-client-protocol.h
	$(CC) $(CFLAGS) -o $@ probe.c $(PROTO)-protocol.c $(WL)

$(PROTO)-client-protocol.h: $(PROTO).xml
	wayland-scanner client-header $< $@

$(PROTO)-protocol.c: $(PROTO).xml
	wayland-scanner private-code $< $@

clean:
	rm -f probe $(PROTO)-protocol.c $(PROTO)-client-protocol.h probe.log

.PHONY: clean
