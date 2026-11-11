# A16 IR illuminator

Research only. Nothing here is installed by `install.sh`.

The investigation is [`docs/a16-ir-illuminator.md`](../../docs/a16-ir-illuminator.md).
The control path on the UX3607OA is unknown. These scripts only collect evidence:

```bash
research/a16-ir-illuminator/collect.sh --self-test
research/a16-ir-illuminator/collect.sh
```

On Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File research/a16-ir-illuminator/collect-windows.ps1
```

Do not commit the evidence directories they write.
