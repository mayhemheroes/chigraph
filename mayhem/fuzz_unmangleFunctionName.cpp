#include <fuzzer/FuzzedDataProvider.h>
#include <stdint.h>
#include <stdio.h>

#include <climits>

#include "chi/NameMangler.hpp"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
	FuzzedDataProvider provider(data, size);
	std::string        mangled = provider.ConsumeBytesAsString(100);
	if (mangled.length() < 10) { return 0; }
	chi::unmangleFunctionName(mangled);

	return 0;
}