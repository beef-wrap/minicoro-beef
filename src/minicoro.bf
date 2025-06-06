/*
Minimal asymmetric stackful cross-platform coroutine library in pure C.
minicoro - v0.2.0 - 15/Nov/2023
Eduardo Bart - edub4rt@gmail.com
https://github.com/edubart/minicoro

Minicoro is single file library for using asymmetric coroutines in C.
The API is inspired by Lua coroutines but with C use in mind.

# Features

- Stackful asymmetric coroutines.
- Supports nesting coroutines (resuming a coroutine from another coroutine).
- Supports custom allocators.
- Storage system to allow passing values between yield and resume.
- Customizable stack size.
- Supports growable stacks and low memory footprint when enabling the virtual memory allocator.
- Coroutine API design inspired by Lua with C use in mind.
- Yield across any C function.
- Made to work in multithread applications.
- Cross platform.
- Minimal, self contained and no external dependencies.
- Readable sources and documented.
- Implemented via assembly, ucontext or fibers.
- Lightweight and very efficient.
- Works in most C89 compilers.
- Error prone API, returning proper error codes on misuse.
- Support running with Valgrind, ASan (AddressSanitizer) and TSan (ThreadSanitizer).

# Supported Platforms

Most platforms are supported through different methods:

| Platform     | Assembly Method  | Fallback Method   |
|--------------|------------------|-------------------|
| Android      | ARM/ARM64        | N/A               |
| iOS          | ARM/ARM64        | N/A               |
| Windows      | x86_64           | Windows fibers    |
| Linux        | x86_64/i686      | ucontext          |
| Mac OS X     | x86_64/ARM/ARM64 | ucontext          |
| WebAssembly  | N/A              | Emscripten fibers / Binaryen asyncify |
| Raspberry Pi | ARM              | ucontext          |
| RISC-V       | rv64/rv32        | ucontext          |

The assembly method is used by default if supported by the compiler and CPU,
otherwise ucontext or fiber method is used as a fallback.

The assembly method is very efficient, it just take a few cycles
to create, resume, yield or destroy a coroutine.

# Caveats

- Avoid using coroutines with C++ exceptions, this is not recommended, it may not behave as you expect.
- When using C++ RAII (i.e. destructors) you must resume the coroutine until it dies to properly execute all destructors.
- Some unsupported sanitizers for C may trigger false warnings when using coroutines.
- The `mco_coro` object is not thread safe, you should use a mutex for manipulating it in multithread applications.
- To use in multithread applications, you must compile with C compiler that supports `thread_local` qualifier.
- Avoid using `thread_local` inside coroutine code, the compiler may cache thread local variables pointers which can be invalid when a coroutine switch threads.
- Stack space is limited. By default it has 56KB of space, this can be changed on coroutine creation, or by enabling the virtual memory backed allocator to make it 2040KB.
- Take care to not cause stack overflows (run out of stack space), otherwise your program may crash or not, the behavior is undefined.
- On WebAssembly you must compile with Emscripten flag `-s ASYNCIFY=1`.
- The WebAssembly Binaryen asyncify method can be used when explicitly enabled,
you may want to do this only to use minicoro with WebAssembly native interpreters
(no Web browser). This method is confirmed to work well with Emscripten toolchain,
however it fails on other WebAssembly toolchains like WASI SDK.

# Introduction

A coroutine represents an independent "green" thread of execution.
Unlike threads in multithread systems, however,
a coroutine only suspends its execution by explicitly calling a yield function.

You create a coroutine by calling `mco_create`.
Its sole argument is a `mco_desc` structure with a description for the coroutine.
The `mco_create` function only creates a new coroutine and returns a handle to it, it does not start the coroutine.

You execute a coroutine by calling `mco_resume`.
When calling a resume function the coroutine starts its execution by calling its body function.
After the coroutine starts running, it runs until it terminates or yields.

A coroutine yields by calling `mco_yield`.
When a coroutine yields, the corresponding resume returns immediately,
even if the yield happens inside nested function calls (that is, not in the main function).
The next time you resume the same coroutine, it continues its execution from the point where it yielded.

To associate a persistent value with the coroutine,
you can  optionally set `user_data` on its creation and later retrieve with `mco_get_user_data`.

To pass values between resume and yield,
you can optionally use `mco_push` and `mco_pop` APIs,
they are intended to pass temporary values using a LIFO style buffer.
The storage system can also be used to send and receive initial values on coroutine creation or before it finishes.

# Usage

To use minicoro, do the following in one .c file:

```c
#define MINICORO_IMPL
#include "minicoro.h"
```

You can do `#include "minicoro.h"` in other parts of the program just like any other header.

## Minimal Example

The following simple example demonstrates on how to use the library:

```c
#define MINICORO_IMPL
#include "minicoro.h"
#include <stdio.h>
#include <assert.h>

// Coroutine entry function.
void coro_entry(mco_coro* co) {
printf("coroutine 1\n");
mco_yield(co);
printf("coroutine 2\n");
}

int main() {
// First initialize a `desc` object through `mco_desc_init`.
mco_desc desc = mco_desc_init(coro_entry, 0);
// Configure `desc` fields when needed (e.g. customize user_data or allocation functions).
desc.user_data = NULL;
// Call `mco_create` with the output coroutine pointer and `desc` pointer.
mco_coro* co;
mco_result res = mco_create(&co, &desc);
assert(res == MCO_SUCCESS);
// The coroutine should be now in suspended state.
assert(mco_status(co) == MCO_SUSPENDED);
// Call `mco_resume` to start for the first time, switching to its context.
res = mco_resume(co); // Should print "coroutine 1".
assert(res == MCO_SUCCESS);
// We get back from coroutine context in suspended state (because it's unfinished).
assert(mco_status(co) == MCO_SUSPENDED);
// Call `mco_resume` to resume for a second time.
res = mco_resume(co); // Should print "coroutine 2".
assert(res == MCO_SUCCESS);
// The coroutine finished and should be now dead.
assert(mco_status(co) == MCO_DEAD);
// Call `mco_destroy` to destroy the coroutine.
res = mco_destroy(co);
assert(res == MCO_SUCCESS);
return 0;
}
```

_NOTE_: In case you don't want to use the minicoro allocator system you should
allocate a coroutine object yourself using `mco_desc.coro_size` and call `mco_init`,
then later to destroy call `mco_uninit` and deallocate it.

## Yielding from anywhere

You can yield the current running coroutine from anywhere
without having to pass `mco_coro` pointers around,
to this just use `mco_yield(mco_running())`.

## Passing data between yield and resume

The library has the storage interface to assist passing data between yield and resume.
It's usage is straightforward,
use `mco_push` to send data before a `mco_resume` or `mco_yield`,
then later use `mco_pop` after a `mco_resume` or `mco_yield` to receive data.
Take care to not mismatch a push and pop, otherwise these functions will return
an error.

## Error handling

The library return error codes in most of its API in case of misuse or system error,
the user is encouraged to handle them properly.

## Virtual memory backed allocator

The new compile time option `MCO_USE_VMEM_ALLOCATOR` enables a virtual memory backed allocator.

Every stackful coroutine usually have to reserve memory for its full stack,
this typically makes the total memory usage very high when allocating thousands of coroutines,
for example, an application with 100 thousands coroutine with stacks of 56KB would consume as high
as 5GB of memory, however your application may not really full stack usage for every coroutine.

Some developers often prefer stackless coroutines over stackful coroutines
because of this problem, stackless memory footprint is low, therefore often considered more lightweight.
However stackless have many other limitations, like you cannot run unconstrained code inside them.

One remedy to the solution is to make stackful coroutines growable,
to only use physical memory on demand when its really needed,
and there is a nice way to do this relying on virtual memory allocation
when supported by the operating system.

The virtual memory backed allocator will reserve virtual memory in the OS for each coroutine stack,
but not trigger real physical memory usage yet.
While the application virtual memory usage will be high,
the physical memory usage will be low and actually grow on demand (usually every 4KB chunk in Linux).

The virtual memory backed allocator also raises the default stack size to about 2MB,
typically the size of extra threads in Linux,
so you have more space in your coroutines and the risk of stack overflow is low.

As an example, allocating 100 thousands coroutines with nearly 2MB stack reserved space
with the virtual memory allocator uses 783MB of physical memory usage, that is about 8KB per coroutine,
however the virtual memory usage will be at 98GB.

It is recommended to enable this option only if you plan to spawn thousands of coroutines
while wanting to have a low memory footprint.
Not all environments have an OS with virtual memory support, therefore this option is disabled by default.

This option may add an order of magnitude overhead to `mco_create()`/`mco_destroy()`,
because they will request the OS to manage virtual memory page tables,
if this is a problem for you, please customize a custom allocator for your own needs.

## Library customization

The following can be defined to change the library behavior:

- `[CLink] public static extern`                   - Public API qualifier. Default is `extern`.
- `MCO_MIN_STACK_SIZE`        - Minimum stack size when creating a coroutine. Default is 32768 (32KB).
- `MCO_DEFAULT_STORAGE_SIZE`  - Size of coroutine storage buffer. Default is 1024.
- `MCO_DEFAULT_STACK_SIZE`    - Default stack size when creating a coroutine. Default is 57344 (56KB). When `MCO_USE_VMEM_ALLOCATOR` is true the default is 2040KB (nearly 2MB).
- `MCO_ALLOC`                 - Default allocation function. Default is `calloc`.
- `MCO_DEALLOC`               - Default deallocation function. Default is `free`.
- `MCO_USE_VMEM_ALLOCATOR`    - Use virtual memory backed allocator, improving memory footprint per coroutine.
- `MCO_NO_DEFAULT_ALLOCATOR`  - Disable the default allocator using `MCO_ALLOC` and `MCO_DEALLOC`.
- `MCO_ZERO_MEMORY`           - Zero memory of stack when poping storage, intended for garbage collected environments.
- `MCO_DEBUG`                 - Enable debug mode, logging any runtime error to stdout. Defined automatically unless `NDEBUG` or `MCO_NO_DEBUG` is defined.
- `MCO_NO_DEBUG`              - Disable debug mode.
- `MCO_NO_MULTITHREAD`        - Disable multithread usage. Multithread is supported when `thread_local` is supported.
- `MCO_USE_ASM`               - Force use of assembly context switch implementation.
- `MCO_USE_UCONTEXT`          - Force use of ucontext context switch implementation.
- `MCO_USE_FIBERS`            - Force use of fibers context switch implementation.
- `MCO_USE_ASYNCIFY`          - Force use of Binaryen asyncify context switch implementation.
- `MCO_USE_VALGRIND`          - Define if you want run with valgrind to fix accessing memory errors.

# License

Your choice of either Public Domain or MIT No Attribution, see end of file.
*/

using System;
using System.Interop;

namespace minicoro_Beef;

public static class minicoro
{
	typealias size_t = uint;
	typealias char = char8;

	/* Coroutine states. */
	public enum mco_state : c_int
	{
		MCO_DEAD = 0, /* The coroutine has finished normally or was uninitialized before finishing. */
		MCO_NORMAL, /* The coroutine is active but not running (that is, it has resumed another coroutine). */
		MCO_RUNNING, /* The coroutine is active and running. */
		MCO_SUSPENDED /* The coroutine is suspended (in a call to yield, or it has not started running yet). */
	}

	/* Coroutine result codes. */
	public enum mco_result : c_int
	{
		MCO_SUCCESS = 0,
		MCO_GENERIC_ERROR,
		MCO_INVALID_POINTER,
		MCO_INVALID_COROUTINE,
		MCO_NOT_SUSPENDED,
		MCO_NOT_RUNNING,
		MCO_MAKE_CONTEXT_ERROR,
		MCO_SWITCH_CONTEXT_ERROR,
		MCO_NOT_ENOUGH_SPACE,
		MCO_OUT_OF_MEMORY,
		MCO_INVALID_ARGUMENTS,
		MCO_INVALID_OPERATION,
		MCO_STACK_OVERFLOW
	}

	/* Coroutine structure. */
	public struct mco_coro
	{
		public void* context;
		public mco_state state;
		public function void(mco_coro* co) func;
		public mco_coro* prev_co;
		public void* user_data;
		public size_t coro_size;
		public void* allocator_data;
		public function void(void* ptr, size_t size, void* allocator_data) dealloc_cb;
		public void* stack_base; /* Stack base address, can be used to scan memory in a garbage collector. */
		public size_t stack_size;
		public c_uchar* storage;
		public size_t bytes_stored;
		public size_t storage_size;
		public void* asan_prev_stack; /* Used by address sanitizer. */
		public void* tsan_prev_fiber; /* Used by thread sanitizer. */
		public void* tsan_fiber; /* Used by thread sanitizer. */
		public size_t magic_number; /* Used to check stack overflow. */
	}

	/* Structure used to initialize a coroutine. */
	public struct mco_desc
	{
		public function void(mco_coro* co) func; /* Entry point function for the coroutine. */
		public void* user_data; /* Coroutine user data, can be get with `mco_get_user_data`. */
		/* Custom allocation interface. */
		public function void*(size_t size, void* allocator_data) alloc_cb; /* Custom allocation function. */
		public function void(void* ptr, size_t size, void* allocator_data) dealloc_cb; /* Custom deallocation function. */
		public void* allocator_data; /* User data pointer passed to `alloc`/`dealloc` allocation functions. */
		public size_t storage_size; /* Coroutine storage size, to be used with the storage APIs. */
		/* These must be initialized only through `mco_init_desc`. */
		public size_t coro_size; /* Coroutine structure size. */
		public size_t stack_size; /* Coroutine stack size. */
	}

	/* Coroutine functions. */

	[CLink] public static extern mco_desc mco_desc_init(function void(mco_coro* co) func, size_t stack_size); /* Initialize description of a coroutine. When stack size is 0 then MCO_DEFAULT_STACK_SIZE is used. */

	[CLink] public static extern mco_result mco_init(mco_coro* co, mco_desc* desc); /* Initialize the coroutine. */

	[CLink] public static extern mco_result mco_uninit(mco_coro* co); /* Uninitialize the coroutine, may fail if it's not dead or suspended. */

	[CLink] public static extern mco_result mco_create(mco_coro** out_co, mco_desc* desc); /* Allocates and initializes a new coroutine. */

	[CLink] public static extern mco_result mco_destroy(mco_coro* co); /* Uninitialize and deallocate the coroutine, may fail if it's not dead or suspended. */

	[CLink] public static extern mco_result mco_resume(mco_coro* co); /* Starts or continues the execution of the coroutine. */

	[CLink] public static extern mco_result mco_yield(mco_coro* co); /* Suspends the execution of a coroutine. */

	[CLink] public static extern mco_state mco_status(mco_coro* co); /* Returns the status of the coroutine. */

	[CLink] public static extern void* mco_get_user_data(mco_coro* co); /* Get coroutine user data supplied on coroutine creation. */


	/* Storage interface functions, used to pass values between yield and resume. */

	[CLink] public static extern mco_result mco_push(mco_coro* co, void* src, size_t len); /* Push bytes to the coroutine storage. Use to send values between yield and resume. */

	[CLink] public static extern mco_result mco_pop(mco_coro* co, void* dest, size_t len); /* Pop bytes from the coroutine storage. Use to get values between yield and resume. */

	[CLink] public static extern mco_result mco_peek(mco_coro* co, void* dest, size_t len); /* Like `mco_pop` but it does not consumes the storage. */

	[CLink] public static extern size_t mco_get_bytes_stored(mco_coro* co); /* Get the available bytes that can be retrieved with a `mco_pop`. */

	[CLink] public static extern size_t mco_get_storage_size(mco_coro* co); /* Get the total storage size. */


	/* Misc functions. */

	[CLink] public static extern mco_coro* mco_running(); /* Returns the running coroutine for the current thread. */

	[CLink] public static extern char* mco_result_description(mco_result res); /* Get the description of a result. */
}