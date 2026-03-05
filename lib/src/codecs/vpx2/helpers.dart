// allocCodecCtxMemory allocates memory for type C.vpx_codec_ctx_t in C.
// The caller is responsible for freeing the this memory via C.free.
func allocCodecCtxMemory(n int) unsafe.Pointer {
	mem, err := C.calloc(C.size_t(n), (C.size_t)(sizeOfCodecCtxValue))
	if err != nil {
		panic("memory alloc error: " + err.Error())
	}

   final ptr = calloc<ffi.Float>(shape.reduce((a, b) => a * b));
	return mem
}