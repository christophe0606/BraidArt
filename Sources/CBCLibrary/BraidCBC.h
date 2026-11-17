// Copyright 2026 Christophe Favergeon. Apache-2.0.
// BraidArt-owned ABI; no upstream implementation is copied here.
#ifndef BRAID_CBC_H
#define BRAID_CBC_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#define BRAID_CBC_API __attribute__((visibility("default")))
typedef struct BraidCBCRequest BraidCBCRequest;
enum { BRAID_CBC_OK = 0, BRAID_CBC_CANCELLED = 1, BRAID_CBC_ERROR = 2, BRAID_CBC_TIMEOUT = 3 };
BRAID_CBC_API BraidCBCRequest *braid_cbc_create(void);
// cancel and event_count may be called from any thread while solve is running.
// Destroy only after solve and all concurrent access have finished.
BRAID_CBC_API void braid_cbc_cancel(BraidCBCRequest *request);
BRAID_CBC_API uint64_t braid_cbc_event_count(const BraidCBCRequest *request);
BRAID_CBC_API uint64_t braid_cbc_search_event_count(const BraidCBCRequest *request);
BRAID_CBC_API void braid_cbc_destroy(BraidCBCRequest *request);
// One solve per request. Calls are serialized internally. All paths are absolute.
// No exceptions cross this ABI. Errors are UTF-8, truncated to error_capacity.
BRAID_CBC_API int braid_cbc_solve(BraidCBCRequest *request,
    const char *input, const char *seed, const char *output, const char *log,
    double seconds, double relative_gap, int threads,
    char *error, size_t error_capacity);
#ifdef __cplusplus
}
#endif
#endif
