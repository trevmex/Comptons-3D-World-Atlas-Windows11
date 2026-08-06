# Contributing

Keep this repository redistributable:

- Do not add Atlas executables, CD images, proprietary media, crash dumps, screenshots, or generated archive mirrors.
- Keep user paths and machine-specific hashes out of source.
- Run the unit tests before submitting changes: `node --test tests/Node` and `Invoke-Pester -Path tests/PowerShell -CI` with Pester 5.
- Test PowerShell/Node syntax and build the native shim before submitting changes.
- Keep `build/Wlbrw32.dll` synchronized with `src/Atlas-WonderLink-Archive.c`; it is the independently authored x86 artifact used by the one-step installer.
- Build the installer with `./installer/Build-AtlasInstaller.ps1`; the GitHub Actions pipeline runs the same tests and publishes installer assets for `v*` tags.
- Document any behavior that depends on the original disc or Windows Video for Windows.
