# safety

`miyoi` communicates with device firmware through reverse-engineered HID feature reports
read-only operations are lower risk, but commands that set DPI, polling rate, lift-off distance, active stage, or button bindings modify persistent or active device state

## before writing settings

- verify that `miyoictl list` reports a supported model and expected PID
- capture the current values with `miyoictl info`, `dpi`, `lod`, `poll`, and `bind ... list`
- use values within the limits advertised for the model
- keep a second mouse or trackpad available in case a binding becomes unusable
- change one setting at a time and read it back before continuing

## limitations

- protocol behavior can differ by firmware version and connection mode
- the project does not provide rollback, transactional writes, or configuration backups
- CLI input validation is limited; malformed or out-of-range values should not be supplied
- firmware flashing, bootloader commands, and macro storage are not documented or supported
- do not use the software on an unsupported PID merely because it shares the same vendor ID

stop using write commands if responses are missing, values read back incorrectly, or the device repeatedly disconnects
reconnect the device and use the vendor's supported recovery process if necessary
