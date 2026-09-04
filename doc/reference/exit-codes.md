# Exit Codes

`flutter_shadcn` returns `0` when a command succeeds and a non-zero process exit code when the command fails. Scripts and CI jobs should use the numeric exit code for control flow and the string label for readable logs.

On macOS or Linux, read the last exit code with:

```bash
echo $?
```

In PowerShell, read it with:

```powershell
$LASTEXITCODE
```

When a command supports `--json`, the response includes the same numeric value in `meta.exitCode`. JSON errors also use the label shown below as the machine-readable error `code` when the command can report one.

## Codes

| Exit code | Label | Meaning | Common causes | What to do |
| --- | --- | --- | --- | --- |
| `0` | `success` | The command completed successfully. | The requested operation finished without a blocking error. | No action needed. |
| `1` | `unknown_error` | An unexpected failure was reported outside a more specific category. | Unhandled runtime errors or unexpected command failures. | Re-run with `--verbose`, then report the command, output, and project `.shadcn` state if it repeats. |
| `2` | `usage_error` | The command syntax or option set is invalid. | Missing required arguments, incompatible flags, non-advanced usage of advanced-only options, or an invalid component address format. | Run the command with `--help`, fix the arguments, and retry. |
| `10` | `registry_not_found` | The selected registry could not be resolved or loaded. | Unknown namespace, missing configured registry, invalid registry path, or no usable registry directory entry. | Run `flutter_shadcn registries` and `flutter_shadcn default`; pass a valid `@namespace` or configure the registry again. |
| `20` | `schema_invalid` | Registry, theme, or generated metadata failed schema validation. | Invalid `registries.json`, component manifest, index, theme payload, or local registry schema. | Validate the registry with `flutter_shadcn validate`; fix the schema error before installing. |
| `30` | `component_missing` | The requested component could not be found or resolved. | Typo in the component name, missing namespace, ambiguous or unavailable component, or dry-run/install target absent from the active registry. | Use `flutter_shadcn list`, `flutter_shadcn search <name>`, or a qualified address such as `@shadcn/button`. |
| `31` | `file_missing` | A required local or registry file is missing. | Manifest references a file that is not present, installed file drift, missing component manifest, or missing generated project file. | Run `flutter_shadcn validate` or `flutter_shadcn audit`; restore the missing file or update the registry manifest. |
| `40` | `network_error` | The CLI needed network access and the fetch failed. | Registry directory, registry metadata, theme payload, or version check request failed while online mode was expected. | Check network access and the registry URL, then retry. Use `--offline` only after the cache has been warmed. |
| `41` | `offline_unavailable` | Offline mode was requested but the needed cached data does not exist. | First run was attempted with `--offline`, or the cache was reset before using offline mode. | Run the same command once online, then retry with `--offline`. |
| `50` | `validation_failed` | Diagnostics found project, registry, dependency, or theme drift. | `doctor`, `audit`, `deps`, `validate`, or theme checks found mismatched dependencies, missing files, invalid config values, or incompatible theme data. | Read the diagnostics output, repair the listed items, then rerun the same command. |
| `60` | `config_invalid` | Project or CLI configuration is invalid. | Invalid `.shadcn/config.json`, invalid `.shadcn/state.json`, unsupported platform target, missing Flutter project files, or malformed locale/theme config. | Fix the JSON or project setup. `flutter_shadcn doctor --json` can identify the failing config section. |
| `70` | `io_error` | The CLI could not read, write, copy, open, or execute a required file operation. | File permission failure, blocked editor/docs launch, failed project cleanup, failed version activation, or path/symlink write rejection. | Check file permissions and paths. Keep generated writes inside the Flutter project root and avoid symlinks that escape it. |

## JSON Shape

Commands that support JSON return the numeric value in `meta.exitCode`:

```json
{
  "meta": {
    "exitCode": 50
  },
  "errors": [
    {
      "code": "validation_failed",
      "message": "Dependency mismatch: ..."
    }
  ]
}
```

Not every command has a JSON mode, but process exit codes are always returned to the shell.

## Automation Guidance

- Use `0` for success and non-zero for failure in CI.
- Use `2` to distinguish command usage mistakes from registry or project problems.
- Treat `10`, `20`, `30`, and `31` as registry/component resolution failures.
- Treat `40` and `41` as fetch/cache failures.
- Treat `50` and `60` as fixable project or registry state failures.
- Treat `70` as an operating-system or filesystem write/read failure.
