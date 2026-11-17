// Copyright 2026 Christophe Favergeon. Apache-2.0.
// Uses the public COIN-OR interfaces; upstream sources remain unmodified.
#include "../Sources/CBCLibrary/BraidCBC.h"
#include "CbcSolver.hpp"
#include "CbcEventHandler.hpp"
#include "ClpEventHandler.hpp"
#include "CoinError.hpp"
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <locale>
#include <memory>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <thread>
#include <unordered_set>

using Clock = std::chrono::steady_clock;
struct BraidCBCRequest {
    std::atomic<bool> cancelled{false};
    std::atomic<bool> used{false};
    std::atomic<uint64_t> events{0};
    std::atomic<uint64_t> searchEvents{0};
    std::atomic<bool> searching{false};
    Clock::time_point deadline;
    std::atomic<bool> timedOut{false};
    bool stopped() {
        if (cancelled.load(std::memory_order_relaxed)) return true;
        if (Clock::now() >= deadline) { timedOut = true; return true; }
        return false;
    }
};

namespace {
// CBC's command driver has process-global parser state even with separate models.
std::mutex solverMutex;
thread_local BraidCBCRequest *activeRequest = nullptr;

class LPEvents final : public ClpEventHandler {
    BraidCBCRequest *request;
public:
    explicit LPEvents(BraidCBCRequest *r) : request(r) {}
    ClpEventHandler *clone() const override { return new LPEvents(*this); }
    int event(Event) override {
        request->events.fetch_add(1, std::memory_order_relaxed);
        // Worker threads only read the deadline and update atomic state.
        return request->cancelled.load(std::memory_order_relaxed) || Clock::now() >= request->deadline ? 0 : -1;
    }
};

class MIPEvents final : public CbcEventHandler {
    BraidCBCRequest *request;
public:
    explicit MIPEvents(BraidCBCRequest *r) : request(r) {}
    CbcEventHandler *clone() const override { return new MIPEvents(*this); }
    CbcAction event(CbcEvent) override {
        request->events.fetch_add(1, std::memory_order_relaxed);
        if (request->searching.load(std::memory_order_relaxed))
            request->searchEvents.fetch_add(1, std::memory_order_relaxed);
        return request->cancelled.load(std::memory_order_relaxed) || Clock::now() >= request->deadline ? stop : noAction;
    }
    CbcAction event(CbcEvent e, void *) override { return event(e); }
};

void installEvents(CbcModel &model, BraidCBCRequest *request) {
    MIPEvents mip(request);
    model.passInEventHandler(&mip);
    if (auto *solver = dynamic_cast<OsiClpSolverInterface *>(model.solver())) {
        LPEvents lp(request);
        solver->getModelPtr()->passInEventHandler(&lp);
    }
}

int stageCallback(CbcModel *model, int stage) {
    // Reattach to models produced by preprocessing, using only public APIs.
    installEvents(*model, activeRequest);
    if (stage == 3) activeRequest->searching.store(true, std::memory_order_relaxed);
    if (stage == 4) activeRequest->searching.store(false, std::memory_order_relaxed);
    return activeRequest->stopped() ? 1 : 0;
}

std::string number(double value) {
    std::ostringstream text;
    text.imbue(std::locale::classic());
    text.precision(17);
    text << value;
    return text.str();
}
void message(char *buffer, size_t capacity, const char *text) noexcept {
    if (buffer && capacity) std::snprintf(buffer, capacity, "%s", text);
}
struct ActiveScope {
    explicit ActiveScope(BraidCBCRequest *request) { activeRequest = request; }
    ~ActiveScope() { activeRequest = nullptr; }
};

// CoinUtils' LP reader is designed for trusted input and can access invalid
// memory on truncated files. Validate BraidArt's deliberately small LP dialect
// before entering it, rather than modifying the upstream parser or trapping a
// fatal signal. This is an independent validator, not copied solver code.
void validateInput(const char *path, BraidCBCRequest *request) {
    std::ifstream file(path);
    if (!file) throw std::runtime_error("Cannot read the CBC partition LP file.");
    std::string line, text;
    while (std::getline(file, line)) {
        if (line.size() > 200) throw std::runtime_error("CBC LP lines must be at most 200 bytes.");
        text += line; text += '\n';
        if (request->stopped()) throw std::runtime_error("CBC input validation interrupted.");
    }
    if (file.bad()) throw std::runtime_error("Cannot finish reading the CBC partition LP file.");
    std::istringstream input(text);
    input.imbue(std::locale::classic());
    auto next = [&]() {
        std::string token;
        if (!(input >> token) || token.size() > 64) throw std::runtime_error("Malformed or truncated CBC partition LP file.");
        return token;
    };
    auto expect = [&](const char *wanted) {
        if (next() != wanted) throw std::runtime_error("Unexpected section in CBC partition LP file.");
    };
    auto variable = [](const std::string &s) {
        if (s.size() < 4 || s[0] != 'x') return false;
        auto underscore = s.find('_');
        if (underscore == std::string::npos || underscore < 2 || underscore + 1 == s.size()) return false;
        for (size_t i = 1; i < s.size(); ++i)
            if (i != underscore && (s[i] < '0' || s[i] > '9')) return false;
        return true;
    };
    auto numeric = [](const std::string &s) {
        std::istringstream value(s);
        value.imbue(std::locale::classic());
        double number;
        if (!(value >> number) || !std::isfinite(number) || value.peek() != std::char_traits<char>::eof())
            throw std::runtime_error("Invalid coefficient in CBC partition LP file.");
    };
    std::unordered_set<std::string> columns, binaries;
    expect("Minimize"); expect("obj:");
    std::string token = next();
    while (token != "Subject") {
        if (token != "+" && token != "-") throw std::runtime_error("Invalid CBC objective.");
        numeric(next());
        auto name = next();
        if (!variable(name) || !columns.insert(name).second) throw std::runtime_error("Invalid CBC objective variable.");
        token = next();
    }
    if (columns.empty()) throw std::runtime_error("Empty CBC objective.");
    expect("To"); token = next();
    size_t rows = 0;
    while (token != "Binary") {
        if (request->stopped()) throw std::runtime_error("CBC input validation interrupted.");
        if (token.size() < 2 || token.front() < 'a' || token.front() > 'z' || token.back() != ':')
            throw std::runtime_error("Missing CBC constraint name.");
        for (size_t i = 0; i + 1 < token.size(); ++i)
            if (!((token[i] >= 'a' && token[i] <= 'z') || (token[i] >= '0' && token[i] <= '9') || token[i] == '_'))
                throw std::runtime_error("Invalid CBC constraint name.");
        token = next();
        size_t terms = 0;
        while (token != "=") {
            if (token != "+" && token != "-") throw std::runtime_error("Invalid CBC constraint.");
            if (!columns.count(next())) throw std::runtime_error("Unknown CBC constraint variable.");
            ++terms; token = next();
        }
        if (!terms) throw std::runtime_error("Empty CBC constraint.");
        token = next();
        if (token != "0" && token != "1") throw std::runtime_error("Invalid CBC constraint bound.");
        ++rows; token = next();
    }
    if (!rows) throw std::runtime_error("Missing CBC constraints.");
    token = next();
    while (token != "End") {
        if (!columns.count(token) || !binaries.insert(token).second) throw std::runtime_error("Invalid CBC binary declaration.");
        token = next();
    }
    if (binaries.size() != columns.size() || (input >> token)) throw std::runtime_error("Incomplete CBC binary declarations.");
}
}

extern "C" {
BraidCBCRequest *braid_cbc_create(void) {
    try { return new BraidCBCRequest; } catch (...) { return nullptr; }
}
void braid_cbc_cancel(BraidCBCRequest *request) {
    if (request) request->cancelled.store(true, std::memory_order_relaxed);
}
uint64_t braid_cbc_event_count(const BraidCBCRequest *request) {
    return request ? request->events.load(std::memory_order_relaxed) : 0;
}
uint64_t braid_cbc_search_event_count(const BraidCBCRequest *request) {
    return request ? request->searchEvents.load(std::memory_order_relaxed) : 0;
}
void braid_cbc_destroy(BraidCBCRequest *request) { delete request; }

int braid_cbc_solve(BraidCBCRequest *request, const char *input, const char *seed,
    const char *output, const char *log, double seconds, double relativeGap, int threads,
    char *error, size_t errorCapacity) {
    message(error, errorCapacity, "");
    try {
        if (!request || !input || !seed || !output || !log ||
            input[0] != '/' || seed[0] != '/' || output[0] != '/' || log[0] != '/' ||
            !std::isfinite(seconds) || seconds < 1 || seconds > 600 ||
            !std::isfinite(relativeGap) || relativeGap < 0 || relativeGap > 0.2 || threads < 1 || threads > 16)
            throw std::invalid_argument("Invalid CBC library arguments.");
        if (request->used.exchange(true)) throw std::invalid_argument("CBC requests cannot be reused.");
        // Waiting for another solve does not consume this partition's time limit.
        std::unique_lock<std::mutex> lock(solverMutex, std::defer_lock);
        while (!lock.try_lock()) {
            if (request->cancelled.load(std::memory_order_relaxed)) return BRAID_CBC_CANCELLED;
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        request->deadline = Clock::now() + std::chrono::milliseconds(static_cast<int64_t>((seconds + 20) * 1000));
        if (request->stopped()) return BRAID_CBC_CANCELLED;
        ActiveScope active(request);
        validateInput(input, request);
        std::unique_ptr<FILE, decltype(&std::fclose)> file(std::fopen(log, "w"), &std::fclose);
        if (!file) throw std::runtime_error("Cannot open the CBC diagnostic file.");
        CoinMessageHandler messages(file.get());
        OsiClpSolverInterface solver;
        solver.passInMessageHandler(&messages);
        solver.setIntParam(OsiNameDiscipline, 1);
        LPEvents lp(request);
        solver.getModelPtr()->passInEventHandler(&lp);
        // Read explicitly: the command driver can otherwise report success after
        // an import error. No arbitrary command strings are accepted by this ABI.
        if (solver.readLp(input) != 0 || solver.getNumCols() == 0)
            throw std::runtime_error("CBC could not read the partition LP file.");
        if (!std::ifstream(seed).good()) throw std::runtime_error("Cannot read the CBC starting solution.");
        if (request->stopped()) return request->timedOut ? BRAID_CBC_TIMEOUT : BRAID_CBC_CANCELLED;
        CbcModel model(solver);
        model.passInMessageHandler(&messages);
        CbcSolverUsefulData data;
        CbcMain0(model, data);
        data.useSignalHandler_ = false; // never replace the app's SIGINT handler
        data.noPrinting_ = true;
        installEvents(model, request);
        // Preserve the current driver defaults, MIP start and solution format.
        // The command driver's solution writer initializes its own name table on
        // import, even when its model already has names. Keep this public import
        // step rather than patching CBC's internal writer.
        std::vector<std::string> args = {"BraidCBC", "-log", "0", "-import", input, "-randomSeed", "1", "-randomCbcSeed", "1",
            "-threads", std::to_string(threads), "-seconds", number(seconds), "-timeMode", "elapsed",
            "-ratioGap", number(relativeGap), "-mipstart", seed, "-solve", "-printingOptions", "normal",
            "-solution", output, "-quit"};
        std::vector<const char *> argv;
        for (const auto &arg : args) argv.push_back(arg.c_str());
        const int status = CbcMain1(static_cast<int>(argv.size()), argv.data(), model, stageCallback, data);
        if (request->stopped()) return request->timedOut ? BRAID_CBC_TIMEOUT : BRAID_CBC_CANCELLED;
        if (status != 0) throw std::runtime_error("CBC returned an unsuccessful solve status.");
        std::ifstream result(output);
        if (!result.good() || result.peek() == std::ifstream::traits_type::eof())
            throw std::runtime_error("CBC did not write a solution file.");
        return BRAID_CBC_OK;
    } catch (const CoinError &e) {
        message(error, errorCapacity, e.message().c_str());
    } catch (const std::exception &e) {
        message(error, errorCapacity, e.what());
    } catch (...) {
        message(error, errorCapacity, "Unknown CBC library failure.");
    }
    if (request && request->cancelled.load(std::memory_order_relaxed)) return BRAID_CBC_CANCELLED;
    return request && request->timedOut ? BRAID_CBC_TIMEOUT : BRAID_CBC_ERROR;
}
}
