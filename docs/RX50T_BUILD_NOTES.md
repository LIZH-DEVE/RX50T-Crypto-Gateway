# RX50T Build Notes

## Current assumption

The first build script assumes:

- part: `xc7a50tfgg484-1`

Reason:

- the provided `A7-50T` resource table contains pins such as `AA18`, `AB22`, `Y18`, `J1`, `K1`
- this strongly suggests an Artix-7 `FGG484` package instead of a smaller `CSG324/CPG236` package

## Important warning

If Vivado rejects the part name, do not modify the RTL first.
Only correct the part argument and rerun:

```powershell
powershell -ExecutionPolicy Bypass -File .\\scripts\\build_rx50t_uart_echo.ps1 <real-part-name>
```

## Default build command

```powershell
powershell -ExecutionPolicy Bypass -File .\\scripts\\build_rx50t_uart_echo.ps1
```

## Output

Synthesis reports are expected under:

- `contest_project/build/rx50t_uart_echo/`

