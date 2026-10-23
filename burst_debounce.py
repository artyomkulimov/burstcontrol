#!/usr/bin/env python3
"""Burst II Air debounce over macOS HID, recovered from official module 1.0.0.15.
Default: read only. Explicit --set-ms changes only the debounce setting.
Tested transport: USB dongle 10f5:5004, interface 1, feature report 3.
"""
import argparse
import json
import time
from pathlib import Path
import hid


def packet(command, payload=b''):
    if len(payload) > 58:
        raise ValueError('Payload too large')
    data = bytearray(64)
    data[0], data[2], data[3], data[5] = 3, command, len(payload), 1
    data[6:6 + len(payload)] = payload
    data[1] = sum(data[2:]) & 255
    return data


class Mouse:
    def __init__(self):
        matches = {d['path']: d for d in hid.enumerate(0x10f5, 0x5004)
                   if d['interface_number'] == 1 and d['usage_page'] == 0xff00}
        if len(matches) != 1:
            raise RuntimeError('Connect exactly one Burst II Air USB dongle')
        self.device = hid.device()
        self.device.open_path(next(iter(matches)))
        self.log = []

    def exchange(self, command, payload=b''):
        request = packet(command, payload)
        self.log.append({'tx': request.hex()})
        if self.device.send_feature_report(request) != 64:
            raise RuntimeError('Incomplete HID write')
        time.sleep(0.05)
        reply = bytes(self.device.get_feature_report(3, 64))
        self.log.append({'rx': reply.hex()})
        if (len(reply) < 5 or reply[:3] != bytes([3, command, 0])
                or len(reply) < 5 + reply[3]):
            raise RuntimeError(f'Unexpected reply: {reply.hex()}')
        body = reply[5:5 + reply[3]]
        if body == b'\xc0\x02':
            raise RuntimeError('Mouse rejected transaction or is busy')
        return body

    def read(self):
        try:
            self.exchange(0x80)
            header = self.exchange(0x82, bytes.fromhex('40000600000000010000'))
            if len(header) != 11 or header[:9] != bytes.fromhex('400006000000000100') or not header[10]:
                raise RuntimeError(f'Unexpected debounce header: {header.hex()}')
            data = self.exchange(0x82, b'\x81' + bytes(57))
            if len(data) != 2 or data[0] != 0x81 or data[1] != header[9] or data[1] > 10:
                raise RuntimeError(f'Invalid debounce data/checksum: {data.hex()}')
            return data[1]
        finally:
            self.exchange(0x81)

    def write(self, value):
        if not 0 <= value <= 10:
            raise ValueError('Debounce must be 0–10 ms')
        try:
            self.exchange(0x80)
            request = bytes.fromhex('400106000000000100') + bytes([value])
            header = self.exchange(0x82, request)
            if len(header) != 11 or header[:10] != request or not header[10]:
                raise RuntimeError(f'Unexpected write header: {header.hex()}')
            self.exchange(0x82, bytes([0x81, value]))
            result = self.exchange(0x82, b'\xc0')
            if result != b'\xc0\x00':
                raise RuntimeError(f'Unexpected commit response: {result.hex()}; read back before retrying')
        finally:
            self.exchange(0x81)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--set-ms', type=int, choices=range(11), metavar='0..10')
    parser.add_argument('--log', type=Path, default=Path('research/last-transaction.json'))
    args = parser.parse_args()
    mouse = Mouse()
    try:
        before = mouse.read()
        print(f'Current debounce: {before} ms')
        if args.set_ms is not None and args.set_ms != before:
            backup = Path('research/debounce-backup.json')
            backup.parent.mkdir(parents=True, exist_ok=True)
            if not backup.exists():
                backup.write_text(json.dumps({'debounce_ms': before, 'vid': '10f5', 'pid': '5004'}, indent=2))
            mouse.write(args.set_ms)
            after = mouse.read()
            print(f'Read-back debounce: {after} ms')
            if after != args.set_ms:
                raise RuntimeError('Read-back does not match requested value')
    finally:
        mouse.device.close()
        args.log.parent.mkdir(parents=True, exist_ok=True)
        args.log.write_text(json.dumps(mouse.log, indent=2))


if __name__ == '__main__':
    main()
