#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
xsens_awinda_converter.py
=========================
Batch-convert Xsens Awinda ``.mtb`` recordings into one ASCII file per IMU,
matching the layout MT Manager produces on a manual export:

    PacketCounter <TAB> Acc_X Acc_Y Acc_Z <TAB> Quat_q0 Quat_q1 Quat_q2 Quat_q3

Uses the official Xsens Device API (same engine as MT Manager), so the numbers
match a manual export.  Works offline on a finished .mtb -- no live sensors.

Run it with the Python that has xsensdeviceapi installed, e.g.:
    py -3.8 xsens_awinda_converter.py .          # convert every .mtb here
    py -3.8 xsens_awinda_converter.py . -o out   # write into out

Data is read two ways for robustness:
  1. the retained packet cache (getDataPacketByIndex), and if that is empty
  2. packets captured via callbacks during loadLogFile.
On an Awinda system the master holds no motion packets -- each MTw child does,
so we always read from the children.
"""

import os
import re
import sys
import glob
import time
import argparse
import threading

try:
    import xsensdeviceapi as xda
except ImportError:
    try:
        import xsensdeviceapi.xsensdeviceapi_py38_64 as xda  # noqa
    except Exception:
        sys.exit(
            "ERROR: could not import 'xsensdeviceapi'. Install the wheel from your\n"
            "MT SDK folder into the SAME Python you run this with, e.g.\n"
            "  py -3.8 -m pip install \"...\\MT SDK\\Python\\x64\\xsensdeviceapi-2022.2.0-cp38-none-win_amd64.whl\""
        )

PC_FMT  = "{:05d}"
NUM_FMT = "{:.6f}"


# ---------------------------------------------------------------------------
# Callback that captures every packet during loadLogFile, keyed by device id.
# (Fallback for when the retained cache does not fill on a given XDA build.)
# ---------------------------------------------------------------------------
class RecordingCallback(xda.XsCallback):
    def __init__(self):
        xda.XsCallback.__init__(self)
        self.lock = threading.Lock()
        self.live = {}   # device id -> [XsDataPacket, ...]
        self.proc = {}

    def _store(self, bucket, dev, packet):
        try:
            did = dev.deviceId().toXsString()
        except Exception:
            return
        with self.lock:
            bucket.setdefault(did, []).append(xda.XsDataPacket(packet))

    # different XDA builds deliver file data through one or the other of these
    def onLiveDataAvailable(self, dev, packet):
        self._store(self.live, dev, packet)

    def onDataAvailable(self, dev, packet):
        self._store(self.proc, dev, packet)

    # Awinda log-file replay is commonly classified as buffered data.  Some
    # XDA builds do not forward this callback to onDataAvailable in Python.
    def onBufferedDataAvailable(self, dev, packet):
        self._store(self.proc, dev, packet)


def _safe(getter, default=""):
    try:
        v = getter()
        return v if v is not None else default
    except Exception:
        return default


def _enable_retain(control):
    """Enable offline processing plus retention so SDI becomes acc/orientation."""
    none_opt = getattr(xda, "XSO_None", 0)
    processing = (getattr(xda, "XSO_Calibrate", 0) |
                  getattr(xda, "XSO_Orientation", 0) |
                  getattr(xda, "XSO_OrientationInBufferedStream", 0))
    for name in ("XSO_RetainRecordingData", "XSO_RetainBufferedData",
                 "XSO_RetainLiveData"):
        opt = getattr(xda, name, None)
        if opt is None:
            continue
        try:
            control.setOptions(opt | processing, none_opt)
            return name, opt | processing
        except Exception:
            continue
    return None, processing


def _xda_version():
    for g in (lambda: xda.xdaVersion().toXsString(), lambda: str(xda.XsVersion_current())):
        v = _safe(g, "")
        if v:
            return v
    return "2022.2.0"


def _write_header(fh, device, coord, delim, euler=False):
    dev_id   = _safe(lambda: device.deviceId().toXsString(), "UNKNOWN")
    product  = _safe(lambda: device.productCode(), "")
    firmware = _safe(lambda: device.firmwareVersion().toXsString(), "")
    hardware = _safe(lambda: device.hardwareVersion().toXsString(), "")
    fprofile = _safe(lambda: device.xdaFilterProfile().toXsString(), "")
    # XDA returns e.g. "46.1 human"; MT Manager displays "human(46.1)".
    match = re.match(r"^([0-9.]+)\s+(.+)$", str(fprofile).strip())
    if match:
        fprofile = "%s(%s)" % (match.group(2), match.group(1))
    fh.write("// General information: \n")
    fh.write("//  MT Manager version: %s \n" % _xda_version())
    fh.write("//  XDA version: %s\n" % _xda_version())
    fh.write("// Device information: \n")
    fh.write("//  DeviceId: %s\n" % dev_id)
    fh.write("//  ProductCode: %s\n" % product)
    fh.write("//  Firmware Version: %s\n" % firmware)
    fh.write("//  Hardware Version: %s\n" % hardware)
    fh.write("// Device settings: \n")
    fh.write("//  Filter Profile: %s\n" % fprofile)
    fh.write("//  Option Flags: Orientation Smoother Disabled, Position/Velocity "
             "Smoother Disabled, Continuous Zero Rotation Update Disabled, "
             "AHS Disabled, ICC Disabled\n")
    fh.write("// Coordinate system: %s\n" % coord)
    header = ["PacketCounter", "Acc_X", "Acc_Y", "Acc_Z",
              "Quat_q0", "Quat_q1", "Quat_q2", "Quat_q3"]
    if euler:
        header += ["Roll", "Pitch", "Yaw"]
    fh.write(delim.join(header) + "\n")


def _quat(packet, coord):
    frames = {"ENU": getattr(xda, "XDI_CoordSysEnu", None),
              "NED": getattr(xda, "XDI_CoordSysNed", None),
              "NWU": getattr(xda, "XDI_CoordSysNwu", None)}
    fid = frames.get(coord.upper())
    if fid is not None:
        try:
            return packet.orientationQuaternion(fid)
        except Exception:
            pass
    return packet.orientationQuaternion()


def _euler(packet, coord):
    frames = {"ENU": getattr(xda, "XDI_CoordSysEnu", None),
              "NED": getattr(xda, "XDI_CoordSysNed", None),
              "NWU": getattr(xda, "XDI_CoordSysNwu", None)}
    fid = frames.get(coord.upper())
    if fid is not None:
        try:
            return packet.orientationEuler(fid)
        except Exception:
            pass
    return packet.orientationEuler()


def _xyz(value):
    """Read Xsens vector/Euler values across SWIG binding variants."""
    try:
        return value[0], value[1], value[2]
    except (TypeError, IndexError):
        return value.x(), value.y(), value.z()


def _row(packet, coord, delim, euler=False):
    pc = _safe(packet.packetCounter, 0)
    cells = [PC_FMT.format(int(pc))]
    if _safe(packet.containsCalibratedAcceleration, False):
        a = packet.calibratedAcceleration()
        cells += [NUM_FMT.format(a[0]), NUM_FMT.format(a[1]), NUM_FMT.format(a[2])]
    else:
        cells += ["", "", ""]
    if _safe(packet.containsOrientation, False):
        q = _quat(packet, coord)
        cells += [NUM_FMT.format(q[0]), NUM_FMT.format(q[1]),
                  NUM_FMT.format(q[2]), NUM_FMT.format(q[3])]
    else:
        cells += ["", "", "", ""]
    if euler:
        if _safe(packet.containsOrientation, False):
            angles = _euler(packet, coord)
            roll, pitch, yaw = _xyz(angles)
            cells += [NUM_FMT.format(roll), NUM_FMT.format(pitch),
                      NUM_FMT.format(yaw)]
        else:
            cells += ["", "", ""]
    return delim.join(cells)


def _packet_content_score(packets):
    """Prefer a packet source containing measurements over counter-only packets."""
    score = 0
    for packet in packets[:min(len(packets), 25)]:
        score += 4 if _safe(packet.containsOrientation, False) else 0
        score += 2 if _safe(packet.containsCalibratedAcceleration, False) else 0
        score += 1 if _safe(packet.containsCalibratedData, False) else 0
    return score


def _packet_summary(packet):
    checks = (
        ("orientation", "containsOrientation"),
        ("calibrated", "containsCalibratedData"),
        ("raw", "containsRawData"),
        ("raw-acc", "containsRawAcceleration"),
        ("raw-gyro", "containsRawGyroscopeData"),
        ("raw-mag", "containsRawMagneticField"),
        ("snapshot", "containsAwindaSnapshot"),
        ("full-snapshot", "containsFullSnapshot"),
        ("sdi", "containsSdiData"),
    )
    return [label for label, method in checks
            if _safe(getattr(packet, method, lambda: False), False)]


def _collect_devices(control, main_device, main_id):
    devices = []
    try:
        ch = main_device.children()
        n = ch.size() if hasattr(ch, "size") else len(ch)
        for i in range(n):
            devices.append(ch[i])
    except Exception:
        pass
    if not devices:
        try:
            for did in control.deviceIds():
                if did != main_id:
                    devices.append(control.device(did))
        except Exception:
            pass
    if not devices:
        devices.append(main_device)
    return devices


def convert_one(mtb_path, out_dir, coord="ENU", as_csv=False, index=0,
                keep_prefix=False, euler=False):
    delim = "," if as_csv else "\t"
    ext   = ".csv" if as_csv else ".txt"
    stem  = os.path.splitext(os.path.basename(mtb_path))[0]
    if not keep_prefix:
        stem = re.sub(r"^\d+_", "", stem)     # drop any leading "<digits>_" prefix
    suffix_idx = "-%03d" % index

    control = xda.XsControl.construct()
    if control is None:
        raise RuntimeError("Failed to construct XsControl")

    callback = RecordingCallback()
    written = []
    try:
        retain, processing_options = _enable_retain(control)
        print("    retain option: %s" % (retain or "NONE FOUND (relying on callbacks)"))

        if not control.openLogFile(mtb_path):
            raise RuntimeError("openLogFile failed (is the .mtb open in MT Manager?)")

        main_ids = control.mainDeviceIds()
        n_main = main_ids.size() if hasattr(main_ids, "size") else len(main_ids)
        if n_main == 0:
            raise RuntimeError("no main device found in file")
        main_id = main_ids[0]
        main_device = control.device(main_id)
        _safe(lambda: main_device.setOptions(processing_options,
                                             getattr(xda, "XSO_None", 0)), None)

        # attach the capture callback to master + every child before loading
        devices = _collect_devices(control, main_device, main_id)
        for d in [main_device] + devices:
            _safe(lambda d=d: d.setOptions(processing_options,
                                           getattr(xda, "XSO_None", 0)), None)
            _safe(lambda d=d: d.addCallbackHandler(callback), None)

        if not main_device.loadLogFile():
            raise RuntimeError("loadLogFile failed")
        try:
            main_device.waitForLoadLogFileDone()
        except Exception:
            while _safe(main_device.isLoadLogFileInProgress, False):
                time.sleep(0.02)
        time.sleep(0.1)  # let any trailing callbacks flush

        for dev in devices:
            dev_id = _safe(lambda: dev.deviceId().toXsString(), "UNKNOWN")

            # Compare all available sources. Some XDA versions populate a
            # counter-only child cache while callbacks contain the full sample.
            n_cache = int(_safe(dev.getDataPacketCount, 0) or 0)
            candidates = []
            if n_cache > 0:
                candidates.append(("cache", [dev.getDataPacketByIndex(i)
                                              for i in range(n_cache)]))
            if callback.proc.get(dev_id):
                candidates.append(("processed callback", callback.proc[dev_id]))
            if callback.live.get(dev_id):
                candidates.append(("live callback", callback.live[dev_id]))

            if candidates:
                source, packets = max(candidates,
                                      key=lambda item: _packet_content_score(item[1]))
            else:
                source, packets = None, None

            if not packets:
                print("    [skip] %s : 0 packets" % dev_id)
                continue

            out_path = os.path.join(out_dir, "%s%s_%s%s" % (stem, suffix_idx, dev_id, ext))
            with open(out_path, "w", newline="") as fh:
                _write_header(fh, dev, coord, delim, euler=euler)
                for p in packets:
                    fh.write(_row(p, coord, delim, euler=euler) + "\n")
            score = _packet_content_score(packets)
            print("    [ok]   %s : %d samples (%s, content score %d) -> %s"
                  % (dev_id, len(packets), source, score, os.path.basename(out_path)))
            if score == 0:
                print("           first-packet fields: %s"
                      % (", ".join(_packet_summary(packets[0])) or "counter/timing only"))
            written.append(out_path)

    finally:
        try:
            control.clearCallbackHandlers()
        except Exception:
            pass
        try:
            control.close()
        except Exception:
            pass
    return written


def find_mtb_files(target, recursive):
    if os.path.isfile(target):
        return [target] if target.lower().endswith(".mtb") else []
    pattern = "**/*.mtb" if recursive else "*.mtb"
    return sorted(glob.glob(os.path.join(target, pattern), recursive=recursive))


def main():
    ap = argparse.ArgumentParser(
        description="Batch-convert Xsens .mtb recordings to per-IMU ASCII files.")
    ap.add_argument("input", help="a .mtb file OR a folder containing .mtb files")
    ap.add_argument("-o", "--out", default=None,
                    help="output folder (default: alongside each input file)")
    ap.add_argument("--coord", default="ENU", choices=["ENU", "NED", "NWU"],
                    help="orientation coordinate frame (default: ENU)")
    ap.add_argument("--csv", action="store_true",
                    help="write comma-separated .csv instead of tab-separated .txt")
    ap.add_argument("--recursive", action="store_true",
                    help="search sub-folders when input is a directory")
    ap.add_argument("--index", type=int, default=0,
                    help="the -NNN part of the output name (default 0 -> '-000')")
    ap.add_argument("--keep-prefix", action="store_true",
                    help="keep any leading '<digits>_' in the filename")
    ap.set_defaults(euler=False)
    ap.add_argument("--euler", dest="euler", action="store_true",
                    help="also export Roll, Pitch, Yaw orientation angles")
    ap.add_argument("--no-euler", dest="euler", action="store_false",
                    help="omit Roll, Pitch, Yaw columns (default)")
    args = ap.parse_args()

    files = find_mtb_files(args.input, args.recursive)
    if not files:
        sys.exit("No .mtb files found at: %s" % args.input)
    if args.out:
        os.makedirs(args.out, exist_ok=True)

    total = 0
    for f in files:
        out_dir = args.out or os.path.dirname(os.path.abspath(f))
        print("Converting: %s" % f)
        try:
            total += len(convert_one(f, out_dir, coord=args.coord, as_csv=args.csv,
                                     index=args.index, keep_prefix=args.keep_prefix,
                                     euler=args.euler))
        except Exception as e:
            print("    [ERROR] %s" % e)
    print("\nDone. Wrote %d IMU file(s) from %d recording(s)." % (total, len(files)))


if __name__ == "__main__":
    main()
