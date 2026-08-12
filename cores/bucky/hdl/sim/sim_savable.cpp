#include "Vtb_bucky_parent.h"
#include "Vtb_bucky_parent___024root.h"
#include "verilated.h"
#include "verilated_save.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>

#if defined(_WIN32)
#include <fcntl.h>
#include <stdlib.h>
#endif

extern "C" int bucky_capture_take_save_request();

static uint64_t simulation_time = 0;
double sc_time_stamp() { return static_cast<double>(simulation_time); }

namespace {

std::string plus_value(int argc, char** argv, const std::string& key) {
    for (int i = 1; i < argc; ++i) {
        const std::string arg{argv[i]};
        if (arg.rfind(key, 0) == 0)
            return arg.substr(key.size());
    }
    return {};
}

uint32_t plus_u32(int argc, char** argv, const std::string& key,
                  uint32_t fallback) {
    const auto value = plus_value(argc, argv, key);
    if (value.empty())
        return fallback;
    char* end = nullptr;
    const auto parsed = std::strtoul(value.c_str(), &end, 0);
    return end && *end == '\0' ? static_cast<uint32_t>(parsed) : fallback;
}

bool has_plus(int argc, char** argv, const std::string& key) {
    for (int i = 1; i < argc; ++i) {
        if (std::string{argv[i]} == key)
            return true;
    }
    return false;
}

void save_state(Vtb_bucky_parent& top, uint64_t half_step,
                const std::string& path) {
    VerilatedSave stream;
    stream.open(path.c_str());
    stream << half_step;
    stream << top;
    stream.close();
    std::cout << "[CHECKPOINT] saved frame=" << top.sim_frames
              << " half_step=" << half_step << " file=" << path
              << std::endl;
}

void restore_state(Vtb_bucky_parent& top, uint64_t& half_step,
                   const std::string& path) {
    VerilatedRestore stream;
    stream.open(path.c_str());
    stream >> half_step;
    stream >> top;
    stream.close();
    std::cout << "[CHECKPOINT] restored frame=" << top.sim_frames
              << " half_step=" << half_step << " file=" << path
              << std::endl;
}

}  // namespace

int main(int argc, char** argv) {
#if defined(_WIN32)
    // MinGW's low-level open() defaults to text translation.  VerilatedSave
    // uses open()/write() for an opaque binary stream, so CRLF conversion
    // corrupts otherwise complete checkpoints unless the process default is
    // changed before Verilator opens the file.
    if (_set_fmode(_O_BINARY) == -1) {
        std::cerr << "[CHECKPOINT] failed to enable binary file mode"
                  << std::endl;
        return 2;
    }
#endif
    // Verilator's $display ultimately writes through stdio.  Keep redirected
    // diagnostics observable a frame at a time instead of in 4 KiB bursts.
    std::setvbuf(stdout, nullptr, _IOLBF, 0);
    std::setvbuf(stderr, nullptr, _IOLBF, 0);

    auto context = std::make_unique<VerilatedContext>();
    context->commandArgs(argc, argv);
    auto top = std::make_unique<Vtb_bucky_parent>(context.get());

    uint64_t half_step = 0;
    const auto restore_path = plus_value(argc, argv, "+RESTORE_STATE=");
    const auto save_path = plus_value(argc, argv, "+SAVE_STATE=");
    const auto requested_frame = plus_u32(argc, argv, "+AUTO_SAVE_FRAME=", 1);
    const bool host_bus_diag = has_plus(argc, argv, "+HOST_BUS_DIAG");
    bool automatic_saved = false;
    bool host_bus_logged = false;

    if (!restore_path.empty()) {
        restore_state(*top, half_step, restore_path);
        simulation_time = half_step * 10;
        context->time(simulation_time);
    } else {
        top->clk = 0;
        top->clk24 = 0;
        top->clk48 = 0;
        top->clk96 = 0;
        top->eval();
    }

    uint32_t last_frame = top->sim_frames;
    while (!context->gotFinish()) {
        ++half_step;
        simulation_time = half_step * 10;
        context->timeInc(10);
        // clk96 is an unused compatibility port in this core and is removed
        // from the generated logic.  Do not evaluate a second empty 5 ns
        // timeslot; all live domains change on the 10 ns grid below.
        top->clk = !top->clk;
        top->clk48 = !top->clk48;
        if ((half_step & 1U) == 0)
            top->clk24 = !top->clk24;
        top->eval();

        // Host-side observability preserves the Verilated model's serialized
        // layout, so an existing pre-input checkpoint remains valid while the
        // first accepted player/object transaction is narrowed.  This is
        // intentionally limited to the gameplay-transition addresses.
        if (host_bus_diag) {
            const auto* const root = top->rootp;
            const uint32_t address =
                (root->tb_bucky_parent__DOT__dut__DOT__u_game__DOT__u_main__DOT__eff_addr
                 << 1U) & 0x00ffffffU;
            const bool selected =
                (address >= 0x080050U && address <= 0x080069U) ||
                (address >= 0x080940U && address <= 0x08094fU) ||
                (address >= 0x091400U && address <= 0x0917ffU) ||
                (address >= 0x003c9aU && address <= 0x003caeU) ||
                address == 0x0da000U;
            const bool bus_active =
                !root->tb_bucky_parent__DOT__dut__DOT__u_game__DOT__u_main__DOT__BUSn;
            const bool write =
                root->tb_bucky_parent__DOT__dut__DOT__u_game__DOT__u_main__DOT__eff_we;
            const bool accepted =
                !root->tb_bucky_parent__DOT__dut__DOT__u_game__DOT__u_main__DOT__dtac_mux;
            if (!bus_active) {
                host_bus_logged = false;
            } else if (!host_bus_logged && selected &&
                       (write || accepted) && top->sim_frames >= 500U) {
                const uint32_t pc =
                    (root->tb_bucky_parent__DOT__dut__DOT__u_game__DOT__u_main__DOT__pc_last
                     << 1U) & 0x00ffffffU;
                const uint32_t dsn = root->tb_bucky_parent__DOT__dut__DOT__ram_dsn;
                const uint32_t data = write
                    ? root->tb_bucky_parent__DOT__dut__DOT__ram_din
                    : root->tb_bucky_parent__DOT__dut__DOT__u_game__DOT__u_main__DOT__cpu_din;
                std::printf("HOST_BUS_%s frame=%u pc=%06x addr=%06x dsn=%02x data=%04x\n",
                            write ? "WR" : "RD", top->sim_frames, pc,
                            address, dsn, data);
                std::fflush(stdout);
                host_bus_logged = true;
            }
        }

        if (top->sim_frames != last_frame) {
            last_frame = top->sim_frames;
            if (!save_path.empty() && !automatic_saved &&
                last_frame >= requested_frame) {
                save_state(*top, half_step, save_path);
                automatic_saved = true;
            }
        }
        if (bucky_capture_take_save_request()) {
            const auto manual_path = save_path.empty()
                ? std::string{"bucky-manual.vltsv"} : save_path;
            save_state(*top, half_step, manual_path);
        }
    }

    top->final();
    return 0;
}
