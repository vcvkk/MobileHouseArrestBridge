#!/usr/bin/env python3
"""
MobileHouseArrest Bridge - PC Client Tool
Connects to the on-device MobileHouseArrest iOS server over USB (iproxy / usbmuxd).
"""

import argparse
import base64
import json
import socket
import sys

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8080


def send_command(command_str: str, host: str = DEFAULT_HOST, port: int = DEFAULT_PORT) -> dict:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5.0)
        s.connect((host, port))
        s.sendall(command_str.encode("utf-8"))

        response_bytes = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            response_bytes += chunk

        s.close()
        return json.loads(response_bytes.decode("utf-8"))
    except ConnectionRefusedError:
        print(f"[!] Error: Could not connect to {host}:{port}.")
        print("    Make sure the iOS app is running and 'iproxy 8080 8080' is active.")
        sys.exit(1)
    except Exception as e:
        print(f"[!] Error communicating with iOS server: {e}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="PC Client for MobileHouseArrest iOS Bridge")
    parser.add_argument("--host", default=DEFAULT_HOST, help="Target host (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Target port (default: 8080)")

    subparsers = parser.add_subparsers(dest="action", help="Action to perform")

    # ping
    subparsers.add_parser("ping", help="Ping the iOS server")

    # activate
    act_parser = subparsers.add_parser("activate", help="Activate container via MobileHouseArrest")
    act_parser.add_argument("--class-id", type=int, default=2, choices=[2, 7, 13],
                            help="Container class (2: AppData, 7: AppGroup, 13: SystemGroup)")
    act_parser.add_argument("--group", action="store_true", help="Set if querying an app group container")
    act_parser.add_argument("identifier", help="Bundle ID or Group ID (e.g., com.apple.mobilephone)")

    # ls
    ls_parser = subparsers.add_parser("ls", help="List directory contents on iOS")
    ls_parser.add_argument("path", help="Absolute path to list")

    # cat / get
    get_parser = subparsers.add_parser("get", help="Download file from iOS device")
    get_parser.add_argument("remote_path", help="Remote file path")
    get_parser.add_argument("local_path", help="Local destination file path")

    # put
    put_parser = subparsers.add_parser("put", help="Upload local file to iOS device")
    put_parser.add_argument("local_path", help="Local source file path")
    put_parser.add_argument("remote_path", help="Remote destination path")

    args = parser.parse_args()

    if not args.action:
        parser.print_help()
        sys.exit(0)

    if args.action == "ping":
        res = send_command("PING", args.host, args.port)
        print(f"[+] Server response: {res.get('message', res)}")

    elif args.action == "activate":
        is_group_int = 1 if args.group else 0
        cmd = f"ACTIVATE {args.class_id} {is_group_int} {args.identifier}"
        res = send_command(cmd, args.host, args.port)
        if res.get("status") == "ok":
            print(f"[+] Successfully escaped sandbox for {args.identifier}!")
            print(f"[+] Container Path: {res.get('path')}")
        else:
            print(f"[-] Activation failed: {res.get('error')}")

    elif args.action == "ls":
        cmd = f"LS {args.path}"
        res = send_command(cmd, args.host, args.port)
        if res.get("status") == "ok":
            print(f"[+] Directory listing for {args.path}:")
            for item in res.get("items", []):
                print(f"  - {item}")
        else:
            print(f"[-] Failed to list directory: {res.get('error')}")

    elif args.action == "get":
        cmd = f"READ {args.remote_path}"
        res = send_command(cmd, args.host, args.port)
        if res.get("status") == "ok":
            data = base64.b64decode(res.get("data", ""))
            with open(args.local_path, "wb") as f:
                f.write(data)
            print(f"[+] Saved {len(data)} bytes to '{args.local_path}'.")
        else:
            print(f"[-] Failed to read file: {res.get('error')}")

    elif args.action == "put":
        try:
            with open(args.local_path, "rb") as f:
                raw_bytes = f.read()
            b64_data = base64.b64encode(raw_bytes).decode("utf-8")
            cmd = f"WRITE {args.remote_path}\n{b64_data}"
            res = send_command(cmd, args.host, args.port)
            if res.get("status") == "ok":
                print(f"[+] Successfully wrote '{args.local_path}' to '{args.remote_path}'.")
            else:
                print(f"[-] Failed to write file: {res.get('error')}")
        except FileNotFoundError:
            print(f"[-] Local file not found: {args.local_path}")


if __name__ == "__main__":
    main()
