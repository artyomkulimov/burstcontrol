# Repository instructions

- Use semantic commit messages.
- Keep vendor binaries, local research, and device logs out of Git.
- Run `./test.sh` for protocol changes; it does not access hardware.
- Hardware writes must be intentional, scoped, and checked by read-back.
- Preserve unmapped bytes; do not expose unverified writable settings.
