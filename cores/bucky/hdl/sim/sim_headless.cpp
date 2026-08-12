#define DPI_DLLISPEC
#include "svdpi.h"

// Headless DPI boundary for the parent integration bench. Native PPM capture
// remains inside tb_bucky_parent; these callbacks deliberately provide no
// display, GUI event loop, SDL dependency, or host-controlled DUT stimulus.
extern "C" void bucky_capture_init(int, int) {}

extern "C" void bucky_capture_frame(const svOpenArrayHandle,
                                    const svOpenArrayHandle,
                                    const svOpenArrayHandle,
                                    int, int) {}

extern "C" void bucky_capture_poll() {}

extern "C" int bucky_capture_take_save_request() {
	return 0;
}

extern "C" void bucky_capture_done() {}
