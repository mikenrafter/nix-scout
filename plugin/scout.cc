// nix-scout plugin-files shim: registers `nix scout` via RegisterCommand and
// execs the nix-scout CLI with the remaining argv.
//
// Important CppNix limitation (verified on 2.34/master): initPlugins() runs
// in RootArgs::initialFlagsProcessed(), *after* MultiCommand resolves the
// top-level subcommand. So `nix scout …` throws "not a recognised command"
// even when this plugin is in plugin-files. Help and NIX_GET_COMPLETIONS still
// see the registration (they reach pluginsInited() before listing).
//
// The package therefore also ships a PATH-priority `nix` wrapper that
// forwards `scout` to nix-scout so invocation works today. Keep this plugin
// so help/completions stay native, and so a future Nix load-order fix makes
// the wrapper unnecessary.

#include "version.hh"

#include <nix/cmd/command.hh>
#include <nix/util/error.hh>

#include <cerrno>
#include <cstring>
#include <string>
#include <unistd.h>
#include <vector>

using namespace nix;

namespace {

// Keep in lockstep with share/subcommands.tsv (tests/plugin-shim.sh checks).
const char *const kSubcommands[] = {
    "list",         "inspect", "new",     "switch", "update",
    "status",       "clear",   "doctor",  "completions", "help",
};

void completeSubcommands(AddCompletions & completions, size_t,
                         std::string_view prefix)
{
    for (const char * name : kSubcommands) {
        if (hasPrefix(name, prefix))
            completions.add(name);
    }
}

} // namespace

struct CmdScout : Command
{
    std::vector<std::string> args;

    CmdScout()
    {
        expectArgs({
            .label = "args",
            .handler = {&args},
            .completer = completeSubcommands,
        });
    }

    std::string description() override
    {
        return "run nix-scout (scout module switcher)";
    }

    Category category() override
    {
        return catUtility;
    }

    void run() override
    {
        std::vector<char *> argv;
        argv.reserve(args.size() + 2);
        argv.push_back(const_cast<char *>("nix-scout"));
        for (auto & a : args)
            argv.push_back(const_cast<char *>(a.c_str()));
        argv.push_back(nullptr);

        execvp("nix-scout", argv.data());
        throw Error("failed to exec nix-scout: %s", strerror(errno));
    }
};

static auto regCmdScout = registerCommand<CmdScout>("scout");
