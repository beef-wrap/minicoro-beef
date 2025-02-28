using System;
using System.Diagnostics;
using static System.Runtime;
using static minicoro_Beef.minicoro;

namespace example;

static class Program
{
	static void* alloc(uint size, void* allocator_data)
	{
		return Internal.StdMalloc((int)size);
	}

	static void dealloc(void* ptr, uint size, void* allocator_data)
	{
		Internal.StdFree(ptr);
	}

	static void coro_entry(mco_coro* co)
	{
		Debug.WriteLine("coroutine 1");
		mco_yield(co);
		Debug.WriteLine("coroutine 2");
	}

	static int Main(params String[] args)
	{
		mco_desc desc = mco_desc_init( => coro_entry, 0);
		// Configure `desc` fields when needed (e.g. customize user_data or allocation functions).
		desc.user_data = null;
		desc.alloc_cb = => alloc;
		desc.dealloc_cb = => dealloc;
		// Call `mco_create` with the output coroutine pointer and `desc` pointer.
		mco_coro* co = ?;


		mco_result res = mco_create(&co, &desc);
		Assert(res == .MCO_SUCCESS);

		// The coroutine should be now in suspended state.
		Assert(mco_status(co) == .MCO_SUSPENDED);

		// Call `mco_resume` to start for the first time, switching to its context.
		res = mco_resume(co); // Should print "coroutine 1".
		Assert(res == .MCO_SUCCESS);

		// We get back from coroutine context in suspended state (because it's unfinished).
		Assert(mco_status(co) == .MCO_SUSPENDED);

		// Call `mco_resume` to resume for a second time.
		res = mco_resume(co); // Should print "coroutine 2".
		Assert(res == .MCO_SUCCESS);

		// The coroutine finished and should be now dead.
		Assert(mco_status(co) == .MCO_DEAD);

		// Call `mco_destroy` to destroy the coroutine.
		res = mco_destroy(co);
		Assert(res == .MCO_SUCCESS);

		return 0;
	}
}