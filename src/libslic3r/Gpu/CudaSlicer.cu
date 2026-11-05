// PRIVATE DIAGNOSTIC BRANCH ONLY: synchronous stdout tracing perturbs timing.
// Never transplant this instrumentation into production or an upstream release.
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "CudaSlicer.hpp"
#include "GpuBatchSafety.hpp"

#include <cuda_runtime.h>

#include <chrono>
#include <atomic>
#include <cinttypes>
#include <cstdio>
#include <cstdint>
#include <mutex>
#include <type_traits>
#include <utility>
#include <Windows.h>

namespace Slic3r::Gpu {
namespace {

uint32_t trace_process_id() noexcept { return GetCurrentProcessId(); }
uint32_t trace_thread_id() noexcept { return GetCurrentThreadId(); }
bool trace_stdout_write(const char* data, size_t bytes) noexcept
{
    const HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD written = 0;
    return output != nullptr && output != INVALID_HANDLE_VALUE &&
           WriteFile(output, data, static_cast<DWORD>(bytes), &written, nullptr) && written == bytes;
}

// CUDA_DIAGNOSTIC_CORE_BEGIN
struct TraceContext { uint64_t batch = 0; const char* phase = "outside"; };
std::atomic<uint64_t> g_trace_sequence {0};
thread_local TraceContext g_trace_context;

size_t trace_format(char* buffer, size_t capacity, uint64_t call, uint64_t batch,
                    uint32_t pid, uint32_t tid, const char* phase, const char* event,
                    const char* operation, const char* kind, int value, int64_t elapsed_us) noexcept
{
    const int count = std::snprintf(buffer, capacity,
        "CUDA_API_TRACE_V1 event=%s call=%" PRIu64 " batch=%" PRIu64 " pid=%" PRIu32 " tid=%" PRIu32
        " phase=%s op=%s kind=%s value=%d elapsed_us=%" PRId64 "\n",
        event, call, batch, pid, tid, phase, operation, kind, value, elapsed_us);
    return count > 0 && static_cast<size_t>(count) < capacity ? static_cast<size_t>(count) : 0;
}

void trace_emit(uint64_t call, const char* event, const char* operation,
                const char* kind, int value, int64_t elapsed_us = 0) noexcept
{
    char buffer[512];
    const size_t bytes = trace_format(buffer, sizeof(buffer), call, g_trace_context.batch,
        trace_process_id(), trace_thread_id(), g_trace_context.phase, event, operation, kind, value, elapsed_us);
    if (bytes != 0)
        (void)trace_stdout_write(buffer, bytes);
}

class TraceRuntimeScope {
    TraceContext m_previous;
    uint64_t m_call;
    const char* m_operation;
public:
    explicit TraceRuntimeScope(const char* operation) noexcept
        : m_previous(g_trace_context), m_call(g_trace_sequence.fetch_add(1, std::memory_order_relaxed) + 1),
          m_operation(operation)
    {
        g_trace_context = {m_call, operation};
        trace_emit(m_call, "ENTER", m_operation, "scope", 0);
    }
    ~TraceRuntimeScope() noexcept
    {
        trace_emit(m_call, "LEAVE", m_operation, "scope", 0);
        g_trace_context = m_previous;
    }
};

template<class Action> auto trace_in_phase(const char* phase, Action&& action) -> decltype(action())
{
    struct RestorePhase {
        const char* previous;
        ~RestorePhase() noexcept { g_trace_context.phase = previous; }
    } restore {g_trace_context.phase};
    g_trace_context.phase = phase;
    return std::forward<Action>(action)();
}

template<class Action> auto trace_cuda_call(const char* operation, Action&& action) -> decltype(action())
{
    using Result = decltype(action());
    const uint64_t call = g_trace_sequence.fetch_add(1, std::memory_order_relaxed) + 1;
    trace_emit(call, "ENTRY", operation, "pending", 0);
    const auto start = std::chrono::steady_clock::now();
    const auto elapsed = [&] { return std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now() - start).count(); };
    if constexpr (std::is_void_v<Result>) {
        std::forward<Action>(action)();
        trace_emit(call, "DONE", operation, "statement_returned", 0, elapsed());
    } else {
        Result result = std::forward<Action>(action)();
        if constexpr (std::is_pointer_v<Result>)
            trace_emit(call, "DONE", operation, "pointer_nonnull", result != nullptr, elapsed());
        else if constexpr (std::is_same_v<Result, bool>)
            trace_emit(call, "DONE", operation, "host_bool", result, elapsed());
        else
            trace_emit(call, "DONE", operation, "cuda_error", static_cast<int>(result), elapsed());
        return result;
    }
}

void trace_mutex(const char* event) noexcept
{
    trace_emit(g_trace_context.batch, event, "g_cuda_mutex", "mutex", 0);
}
// CUDA_DIAGNOSTIC_CORE_END

struct CudaRequest {
    int64_t ax, ay, bx, by, scan_x;
    uint64_t stable_id;
};
struct CudaResult {
    int64_t numerator, denominator;
    uint64_t stable_id;
    uint32_t valid;
};

__global__ void vertical_intersection_kernel(const CudaRequest* requests, CudaResult* results, size_t count)
{
    const size_t index = size_t(blockIdx.x) * blockDim.x + threadIdx.x;
    if (index >= count)
        return;
    const CudaRequest request = requests[index];
    CudaResult result {0, 1, request.stable_id, 0};
    const int64_t lower_x = min(request.ax, request.bx);
    const int64_t upper_x = max(request.ax, request.bx);
    if (request.ax != request.bx && request.scan_x > lower_x && request.scan_x < upper_x) {
        const bool forward = request.bx > request.ax;
        const int64_t t = forward ? request.scan_x - request.ax : request.ax - request.scan_x;
        result.denominator = forward ? request.bx - request.ax : request.ax - request.bx;
        // Host preflight proves each raw-coordinate intermediate fits int64.
        result.numerator = t * (request.by - request.ay) + request.ay * result.denominator;
        result.valid = 1;
    }
    results[index] = result;
}

std::mutex g_cuda_mutex;
int g_device = -1;
bool g_qualified = false;
uint32_t g_maximum_grid_x = 0;
constexpr uint32_t block_size = 128;

bool check(cudaError_t error, std::string& diagnostic, const char* operation)
{
    if (error == cudaSuccess)
        return true;
    diagnostic = std::string(operation) + " failed: " + trace_cuda_call("error.cudaGetErrorString", [&] { return cudaGetErrorString(error); });
    return false;
}

bool query_locked(CudaSlicerCapabilities& capabilities)
{
    int count = 0;
    if (!check(trace_cuda_call("query.cudaGetDeviceCount", [&] { return cudaGetDeviceCount(&count); }), capabilities.diagnostic, "cudaGetDeviceCount") || count == 0) {
        if (capabilities.diagnostic.empty())
            capabilities.diagnostic = "No CUDA device was found.";
        return false;
    }
    cudaDeviceProp properties {};
    if (!check(trace_cuda_call("query.cudaGetDeviceProperties", [&] { return cudaGetDeviceProperties(&properties, 0); }), capabilities.diagnostic, "cudaGetDeviceProperties"))
        return false;
    capabilities.runtime_available = true;
    capabilities.device_name = properties.name;
    capabilities.multiprocessors = uint32_t(properties.multiProcessorCount);
    capabilities.max_threads_per_block = uint32_t(properties.maxThreadsPerBlock);
    capabilities.diagnostic = "CUDA device " + capabilities.device_name + " is available.";
    return true;
}

bool dispatch_locked(const std::vector<VerticalIntersectionRequest>& requests,
                     std::vector<VerticalIntersection>& intersections,
                     double& elapsed_ms, std::string& diagnostic)
{
    intersections.clear();
    if (!preflight_vertical_batch(requests)) {
        diagnostic = "CUDA numeric domain or bounded batch contract rejected.";
        return false;
    }
    const size_t grid_size = (requests.size() + block_size - 1) / block_size;
    if (grid_size > g_maximum_grid_x ||
        !check(trace_cuda_call("dispatch.cudaSetDevice", [&] { return cudaSetDevice(g_device); }), diagnostic, "cudaSetDevice"))
        return false;

    std::vector<CudaRequest> host_requests;
    host_requests.reserve(requests.size());
    for (const auto& request : requests)
        host_requests.push_back({request.segment.a.x, request.segment.a.y,
                                 request.segment.b.x, request.segment.b.y,
                                 request.scan_x, request.stable_id});
    std::vector<CudaResult> host_results(requests.size());
    // maximum_intersection_requests bounds these byte and grid calculations.
    const size_t request_bytes = host_requests.size() * sizeof(CudaRequest);
    const size_t result_bytes = host_results.size() * sizeof(CudaResult);
    CudaRequest* device_requests = nullptr;
    CudaResult* device_results = nullptr;
    if (!check(trace_cuda_call("dispatch.cudaMalloc.requests", [&] { return cudaMalloc(&device_requests, request_bytes); }), diagnostic, "cudaMalloc(requests)"))
        return false;
    if (!check(trace_cuda_call("dispatch.cudaMalloc.results", [&] { return cudaMalloc(&device_results, result_bytes); }), diagnostic, "cudaMalloc(results)")) {
        trace_cuda_call("dispatch.cleanup.cudaFree.requests", [&] { return cudaFree(device_requests); });
        return false;
    }
    bool success = check(trace_cuda_call("dispatch.cudaMemcpy.requests", [&] { return cudaMemcpy(device_requests, host_requests.data(), request_bytes, cudaMemcpyHostToDevice); }),
                         diagnostic, "cudaMemcpy(requests)");
    if (success) {
        const auto start = std::chrono::steady_clock::now();
        trace_cuda_call("dispatch.kernel_launch_expression", [&] { vertical_intersection_kernel<<<uint32_t(grid_size), block_size>>>(device_requests, device_results, requests.size()); });
        success = check(trace_cuda_call("dispatch.cudaGetLastError", [&] { return cudaGetLastError(); }), diagnostic, "CUDA kernel launch") &&
                  check(trace_cuda_call("dispatch.cudaDeviceSynchronize", [&] { return cudaDeviceSynchronize(); }), diagnostic, "CUDA kernel synchronization");
        elapsed_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    }
    if (success)
        success = check(trace_cuda_call("dispatch.cudaMemcpy.results", [&] { return cudaMemcpy(host_results.data(), device_results, result_bytes, cudaMemcpyDeviceToHost); }),
                        diagnostic, "cudaMemcpy(results)");
    const cudaError_t free_results = trace_cuda_call("dispatch.cudaFree.results", [&] { return cudaFree(device_results); });
    const cudaError_t free_requests = trace_cuda_call("dispatch.cudaFree.requests", [&] { return cudaFree(device_requests); });
    if (success)
        success = check(free_results, diagnostic, "cudaFree(results)") &&
                  check(free_requests, diagnostic, "cudaFree(requests)");
    if (!success)
        return false;
    intersections.reserve(host_results.size());
    for (const auto& result : host_results)
        intersections.push_back({result.numerator, result.denominator, result.stable_id, result.valid == 1});
    diagnostic = "CUDA exact vertical-intersection kernel completed.";
    return true;
}

bool prepare_locked(std::string& diagnostic)
{
    if (g_qualified)
        return check(trace_cuda_call("prepare.ready.cudaSetDevice", [&] { return cudaSetDevice(g_device); }), diagnostic, "cudaSetDevice");
    CudaSlicerCapabilities capabilities;
    if (!query_locked(capabilities) || !check(trace_cuda_call("prepare.first.cudaSetDevice", [&] { return cudaSetDevice(0); }), diagnostic, "cudaSetDevice")) {
        if (diagnostic.empty()) diagnostic = capabilities.diagnostic;
        return false;
    }
    cudaDeviceProp properties {};
    cudaFuncAttributes attributes {};
    if (!check(trace_cuda_call("prepare.cudaGetDeviceProperties", [&] { return cudaGetDeviceProperties(&properties, 0); }), diagnostic, "cudaGetDeviceProperties") ||
        !check(trace_cuda_call("prepare.cudaFuncGetAttributes", [&] { return cudaFuncGetAttributes(&attributes, vertical_intersection_kernel); }), diagnostic, "CUDA kernel image compatibility") ||
        properties.maxThreadsPerBlock < int(block_size) || attributes.maxThreadsPerBlock < int(block_size) ||
        properties.maxGridSize[0] <= 0)
        return false;
    g_device = 0;
    g_maximum_grid_x = uint32_t(properties.maxGridSize[0]);
    // Qualify reversed edges, signs and translated coordinates before any
    // live output is accepted. The same wide oracle validates the entire set.
    std::vector<VerticalIntersectionRequest> requests;
    for (uint64_t index = 0; index < 2048; ++index) {
        const Coord left = -500'000 + Coord(index % 97) * 101;
        const Coord right = left + 1003 + Coord(index % 89);
        const bool reverse = (index & 1) != 0;
        requests.push_back({{{reverse ? right : left, -750'000 + Coord(index) * 37},
                             {reverse ? left : right, 950'000 - Coord(index) * 53}},
                            left + 1 + Coord(index % uint64_t(right - left - 1)), index});
    }
    VerticalIntersectionBatch qualification;
    qualification.dispatched = trace_in_phase("qualification", [&] { return dispatch_locked(requests, qualification.intersections, qualification.gpu_elapsed_ms, diagnostic); });
    if (!trace_cuda_call("qualification.cpu_validate", [&] { return validate_vertical_batch(requests, qualification); })) {
        diagnostic = "CUDA complete exact-integer qualification failed: " + diagnostic;
        return false;
    }
    g_qualified = true;
    diagnostic = capabilities.diagnostic;
    return true;
}

} // namespace

bool cuda_runtime_query(CudaSlicerCapabilities& capabilities)
{
    TraceRuntimeScope trace_scope("runtime.query");
    trace_mutex("WAIT");
    std::lock_guard<std::mutex> lock(g_cuda_mutex);
    trace_mutex("ACQUIRED");
    return query_locked(capabilities);
}

bool cuda_runtime_prepare(std::string& diagnostic)
{
    TraceRuntimeScope trace_scope("runtime.prepare");
    trace_mutex("WAIT");
    std::lock_guard<std::mutex> lock(g_cuda_mutex);
    trace_mutex("ACQUIRED");
    return prepare_locked(diagnostic);
}

bool cuda_runtime_dispatch(const std::vector<VerticalIntersectionRequest>& requests,
                           std::vector<VerticalIntersection>& intersections,
                           double& elapsed_ms, std::string& diagnostic)
{
    TraceRuntimeScope trace_scope("runtime.dispatch");
    // Check before selecting a device or constructing a runtime context.
    if (!preflight_vertical_batch(requests))
        return false;
    trace_mutex("WAIT");
    std::lock_guard<std::mutex> lock(g_cuda_mutex);
    trace_mutex("ACQUIRED");
    return prepare_locked(diagnostic) && trace_in_phase("live", [&] { return dispatch_locked(requests, intersections, elapsed_ms, diagnostic); });
}

void cuda_runtime_release()
{
    TraceRuntimeScope trace_scope("runtime.release");
    // All per-dispatch buffers are already freed. Never reset a device-wide
    // CUDA context: the process may have other independent users of it.
    trace_mutex("WAIT");
    std::lock_guard<std::mutex> lock(g_cuda_mutex);
    trace_mutex("ACQUIRED");
    g_qualified = false;
    g_device = -1;
}

} // namespace Slic3r::Gpu
