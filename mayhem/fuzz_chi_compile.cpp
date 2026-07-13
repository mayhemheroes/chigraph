#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

#include <chi/Context.hpp>
#include <chi/GraphModule.hpp>
#include <chi/LangModule.hpp>
#include <chi/Support/Result.hpp>
#include <chi/Support/json.hpp>

using namespace chi;

// In-process harness for the historical `chi` target (`chi compile <file>.chimod`).
//
// The old target shelled out to the `chi compile` CLI over a file, but that path is not
// fuzzable under sanitizers: the CLI resolves the input relative to a chigraph *workspace*
// and asserts (aborts) on essentially every free-form input before any module code runs
// (Context::loadModule "Name should not be empty"). That is a fixed setup abort, not a
// discoverable defect, so it produces a crash-on-every-input target with no useful edges.
//
// Per the harness policy we convert it to an in-process libFuzzer harness over the SAME code
// path the CLI drives once the file is located: parse the .chimod JSON and deserialize it into
// a GraphModule (loadModule -> addModuleFromJson -> jsonToGraphModule). This exercises the JSON
// module deserializer/validator — the real attack surface of `chi compile` — across every input.
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
	std::string input(reinterpret_cast<const char *>(data), size);

	nlohmann::json j;
	try {
		j = nlohmann::json::parse(input);
	} catch (...) {
		return 0;
	}

	Context c{};
	c.addModule(std::make_unique<LangModule>(c));

	GraphModule *mod = nullptr;
	Result       res = c.addModuleFromJson("fuzz", j, &mod);
	(void)res;

	return 0;
}
