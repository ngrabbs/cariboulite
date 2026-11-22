# CaribouLite HiF TX on Raspberry Pi Zero 2 W

This branch builds on [Matteo Serva’s transmission work](https://github.com/cariboulabs/cariboulite/pull/197). It was exercised on a 64-bit Raspberry Pi OS Lite Zero 2 W, kernel `6.18.50+rpt-rpi-v8`, with the two-port CaribouLite 6G. The original RX installation used [Habraken’s SoapySDR build](https://github.com/Habraken/cariboulite/tree/5a0796390ee7f91e2b260d69e6c71a09c756ba86). The tested changes are firmware, a kernel API compatibility patch, and a standalone TX utility. The examples assume the board is already enumerated as `/dev/smi` and SPI1 exposes three chip selects.

## Changes and evidence

- Synchronize the SMI write strobe and sample data in the FPGA system clock domain. Preserve binary encoding for the byte parser in Yosys.
- Queue each complete I/Q pair across the FPGA clock boundary, signal backpressure ahead of a full FIFO, and preserve all modem sample bits.
- Match the modem and FPGA spacing at the requested sample rate in Hz. At 2 MS/s, readback was `TXDFE=0x82 FPGA_GAP=1`.
- The replay wrapper uses SMI write strobe 12, resets the FPGA stream state, and gives DMA time to drain. The test utility uses minimum power and reports accepted samples and modem state.
- Confirmed HiF narrow-FM voice in both directions at 446.025 MHz. The Pi replayed 10,485,760 complex samples with zero short writes and a handheld recovered the ID over the air after reboot. HiF RX sustained about 2.00 MS/s on repeat testing.

Treat 2 MS/s on HiF as the validated profile. Transmit only on a frequency and with a waveform authorized for your station. For a conducted test, use a suitable load, attenuation, and instrument input limits.

## Build

Build the firmware on a Linux host with Icarus Verilog, Yosys, nextpnr-ice40 with LP1K/QN84 support, and IceStorm. The tested place-and-route seed was 16. Check that both `w_clock_sys` and `lvds_clock_buf` pass their 64 MHz constraints. Different tool versions may produce a different image. The tested image SHA-256 was `9f32d0da94b028c6015105f2308631c4b7723f6fbbba207e149937ae570a0677`.

```sh
iverilog -g2012 -s tb -o /tmp/caribou-smi-sim contrib/pi-zero-2w/smi_rx_tb.v firmware/smi_rx.v
vvp /tmp/caribou-smi-sim
cd firmware
yosys -Q -T -p 'synth_ice40 -abc2 -dffe_min_ce_use 12 -top top -json top.json' top.v
nextpnr-ice40 --lp1k --package qn84 --json top.json --pcf io.pcf \
  --asc top.asc --freq 80 --parallel-refine --opt-timing --seed 16
icepack top.asc top.bin
cd ..
```

On the target, install the development tools and **headers that match the running kernel**. Build from the branch checkout at `-j2` on a Zero 2 W. Supply the host-built `firmware/top.bin` in that checkout.

```sh
mkdir -p driver/build-native
cp driver/*.c driver/*.h driver/build-native/
printf '%s\n' 'obj-m += smi_stream_dev.o' 'ccflags-y += -O2' > driver/build-native/Makefile
make -j2 -C "/lib/modules/$(uname -r)/build" M="$PWD/driver/build-native" modules

cc -O2 -o /tmp/caribou-generate-blob software/utils/generate_bin_blob.c
/tmp/caribou-generate-blob firmware/top.bin cariboulite_firmware \
  software/libcariboulite/src/cariboulite_fpga_firmware.h
/tmp/caribou-generate-blob driver/build-native/smi_stream_dev.ko smi_stream_dev \
  software/libcariboulite/src/caribou_smi/kernel/smi_stream_dev_gen.h
bash scripts/build-standalone.sh all --native
```

## Start at boot

Use a known-good base install with `dtparam=i2c_vc=on` and `dtoverlay=spi1-3cs` in the active boot config, the CaribouLite SMI device tree node, the vendor `bcm2835_smi` dependency, and a udev rule granting the `gpio` group access to `/dev/smi`. Verify the board and that no process is using the radio before changing its driver.

The module overlay preserves the original kernel module. Back up the existing CaribouLite modprobe file and keep the previous firmware available before installing the fixed files. `cariboulite-fpga.service` verifies the loaded module source version before programming the FPGA. Replace its version check if your build emits a different source version.

```sh
sudo install -d -m 0755 /opt/cariboulite-fixed
module_dir="/lib/modules/$(uname -r)/updates/cariboulite"
sudo install -D -m 0644 driver/build-native/smi_stream_dev.ko "$module_dir/smi_stream_dev.ko"
sudo depmod -a
sudo install -m 0644 firmware/top.bin /opt/cariboulite-fixed/paired-timing.bin
sudo install -m 0755 software/flash_fpga/build/flash_fpga /opt/cariboulite-fixed/flash-fpga
sudo install -m 0755 software/tx_test/build/tx_test /opt/cariboulite-fixed/tx-test
sudo install -m 0755 contrib/pi-zero-2w/cariboulite-tx /usr/local/bin/cariboulite-tx

modver=$(/usr/sbin/modinfo -F srcversion "$module_dir/smi_stream_dev.ko")
test -n "$modver"
test "$modver" = "$(/usr/sbin/modinfo -F srcversion smi_stream_dev)"
sed "s/3FA1F1E285C1BBE12021467/$modver/" contrib/pi-zero-2w/cariboulite-fpga.service |
  sudo tee /etc/systemd/system/cariboulite-fpga.service >/dev/null
printf '%s\n' 'options smi_stream_dev fifo_mtu_multiplier=6 addr_dir_offset=2 addr_ch_offset=3' |
  sudo tee /etc/modprobe.d/cariboulite.conf >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable cariboulite-fpga.service
sudo reboot
```

After reconnecting, check the boot log, the loaded module, and the RX rate.

```sh
systemctl is-active cariboulite-fpga
journalctl -b -u cariboulite-fpga
cat /sys/module/smi_stream_dev/srcversion
timeout 15s SoapySDRUtil --args='driver=Cariboulite,channel=HiF' --direction=RX --rate=2000000
```

The service programs the FPGA and leaves RF idle. `cariboulite-tx` runs the test utility explicitly. For a link-only check, pass `CARIBOU_SYNC_ONLY=1` and select HiF with `-c 1`. Set the intended frequency in Hz with `-f`, and supply a bounded signed interleaved I/Q file and `-r 2000000`. Inspect the `SYNC_ONLY` line for modem sync with EEC off and the radio held in TXPREP. For RF replay use a file generated at the same sample rate, with a whole number of 131,072-complex-sample blocks as tested. File playback and the paced driver were validated. Live GNU Radio TX and packet telemetry still need bench validation.

To roll back, disable the FPGA service, move the module out of the kernel module tree, restore the original modprobe file, run `sudo depmod -a`, and reboot. The stock userspace can then load its original FPGA image. Rebuild the overlay module for any new kernel.
